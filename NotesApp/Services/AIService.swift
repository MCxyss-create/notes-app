import Foundation
import Network
import SwiftData

/// Настройки DeepSeek: адрес и модель — в UserDefaults, ключ — в связке ключей.
enum AISettings {
    static let keyAccount = "deepseek-api-key"

    static var apiKey: String? {
        guard let key = KeychainStore.read(keyAccount)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return nil }
        return key
    }

    static var hasKey: Bool { apiKey != nil }

    static func config() throws -> AIConfig {
        guard let key = apiKey else { throw AIError.noKey }
        let defaults = UserDefaults.standard
        guard let url = AIConfig.url(from: defaults.string(forKey: SettingsKeys.aiEndpoint) ?? "") else {
            throw AIError.badEndpoint
        }
        let model = (defaults.string(forKey: SettingsKeys.aiModel) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return AIConfig(endpoint: url, model: model.isEmpty ? AIConfig.defaultModel : model, apiKey: key)
    }

    static var parseDefaults: ParseDefaults {
        ParseDefaults(hour: AppDefaults.hour, minute: AppDefaults.minute, beforeMin: AppDefaults.beforeMin)
    }

    /// Обычный календарь в поясе телефона: от него ИИ считает «завтра» и «в пятницу».
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "ru_RU")
        return calendar
    }
}

/// Разбор фразы через DeepSeek и сохранение того, что подтвердили.
enum AIService {
    /// Спрашивает DeepSeek. Возвращает ответ модели (JSON-строку) — его можно хранить во «Входящих».
    static func ask(_ phrase: String, said reference: Date) async throws -> String {
        let config = try AISettings.config()
        let defaults = AISettings.parseDefaults
        let system = AIPrompt.system(now: reference, calendar: AISettings.calendar, defaultHour: defaults.hour,
                                     defaultMinute: defaults.minute, defaultBefore: defaults.beforeMin)
        return try await DeepSeekClient.send(config: config, system: system, phrase: phrase)
    }

    static func parse(_ content: String, said reference: Date) throws -> AIResult {
        try AIParser.parse(content, reference: reference, now: Date(), defaults: AISettings.parseDefaults,
                           calendar: AISettings.calendar)
    }

    /// Сохраняет отмеченные карточки как записи.
    @MainActor
    static func save(_ drafts: [AIDraft], phrase: String, source: ItemSource = .ai, context: ModelContext) {
        for draft in drafts where draft.include {
            let dated = draft.kind == .reminder ? draft.due : nil
            let item = Item(
                kind: draft.kind,
                title: draft.title,
                body: draft.body,
                dueAt: dated,
                timeGiven: draft.timeGiven,
                remindBeforeMin: dated != nil ? draft.remindBeforeMin : nil,
                repeatRule: dated != nil ? draft.repeatRule : nil,
                tags: draft.tags,
                rawInput: phrase,
                source: source
            )
            context.insert(item)
        }
        try? context.save()
    }
}

/// «Входящие»: фразы, которые не разобрались сразу. Разбирает их сам, когда есть сеть и ключ;
/// результат ждёт подтверждения на карточках.
@MainActor
final class InboxProcessor {
    static let shared = InboxProcessor()

    private var context: ModelContext?
    private let monitor = NWPathMonitor()
    private var started = false
    private var isRunning = false

    private init() {}

    func start(context: ModelContext) {
        self.context = context
        guard !started else { return }
        started = true
        // Сеть появилась — разбираем, что накопилось.
        monitor.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                await InboxProcessor.shared.run()
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.mysli.notes.network"))
    }

    func kick() {
        Task { await run() }
    }

    /// Ключ поменяли — пробуем заново и те фразы, что упали с ошибкой.
    func keyChanged() async {
        guard let context, let entries = try? context.fetch(FetchDescriptor<InboxEntry>()) else { return }
        for entry in entries where entry.parsedJSON == nil {
            entry.lastError = nil
        }
        try? context.save()
        await run()
    }

    /// Разбирает фразы по очереди. retryFailed — заново и те, где была ошибка.
    func run(retryFailed: Bool = false) async {
        guard !isRunning, let context, AISettings.hasKey else { return }
        isRunning = true
        defer { isRunning = false }

        let descriptor = FetchDescriptor<InboxEntry>(sortBy: [SortDescriptor(\.createdAt)])
        guard let entries = try? context.fetch(descriptor) else { return }
        let jobs = entries
            .filter { $0.parsedJSON == nil && (retryFailed || $0.lastError == nil) }
            .map { (id: $0.uid, text: $0.text, said: $0.createdAt) }

        for job in jobs {
            do {
                let content = try await AIService.ask(job.text, said: job.said)
                _ = try AIService.parse(content, said: job.said)
                update(job.id) { entry in
                    entry.parsedJSON = content
                    entry.lastError = nil
                }
            } catch {
                let problem = AIError.from(error)
                update(job.id) { entry in
                    entry.lastError = problem.isTemporary ? nil : problem.message
                }
                // Непонятный ответ — беда только этой фразы. Остальное (сеть, ключ) — у всех, ждём.
                if case .badResponse(_) = problem { continue }
                break
            }
        }
    }

    /// Пока ждали DeepSeek, фразу могли удалить — ищем её заново по uid.
    private func update(_ id: UUID, _ change: (InboxEntry) -> Void) {
        guard let context else { return }
        var descriptor = FetchDescriptor<InboxEntry>(predicate: #Predicate<InboxEntry> { $0.uid == id })
        descriptor.fetchLimit = 1
        guard let entry = try? context.fetch(descriptor).first else { return }
        change(entry)
        try? context.save()
    }
}
