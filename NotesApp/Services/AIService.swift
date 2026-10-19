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
    /// known — записи, которые уже есть: ИИ видит их заголовки и сроки и понимает команды.
    /// folders — папки: ИИ раскладывает по ним идеи и заметки.
    static func ask(_ phrase: String, said reference: Date, known: [AIKnownItem] = [],
                    folders: [AIKnownFolder] = []) async throws -> String {
        let config = try AISettings.config()
        let defaults = AISettings.parseDefaults
        let system = AIPrompt.system(now: reference, calendar: AISettings.calendar, defaultHour: defaults.hour,
                                     defaultMinute: defaults.minute, defaultBefore: defaults.beforeMin,
                                     known: AIContext.forPrompt(known), folders: folders)
        return try await DeepSeekClient.send(config: config, system: system, phrase: phrase)
    }

    static func parse(_ content: String, said reference: Date, known: [AIKnownItem] = [],
                      folders: [AIKnownFolder] = []) throws -> AIResult {
        try AIParser.parse(content, reference: reference, now: Date(), defaults: AISettings.parseDefaults,
                           calendar: AISettings.calendar, known: known, folders: folders)
    }

    /// Все папки с путями — для промта и разбора ответа.
    @MainActor
    static func knownFolders(_ context: ModelContext) -> [AIKnownFolder] {
        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        return AIKnownFolder.list(folders.map(\.node))
    }

    /// Все несделанные записи — для команд. Сделанные ИИ не показываем.
    @MainActor
    static func knownItems(_ context: ModelContext) -> [AIKnownItem] {
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        return items.filter { !$0.isDone }.map(AIKnownItem.init(item:))
    }

    /// Применяет отмеченные изменения. allowDelete=false — для Siri: удалять без карточки нельзя.
    /// Возвращает то, что получилось применить.
    @MainActor
    @discardableResult
    static func apply(_ changes: [AIChange], context: ModelContext, now: Date = Date(),
                      allowDelete: Bool = true) -> [AIChange] {
        var applied: [AIChange] = []
        for change in changes where change.include {
            let id = change.target.uid
            var descriptor = FetchDescriptor<Item>(predicate: #Predicate<Item> { $0.uid == id })
            descriptor.fetchLimit = 1
            guard let item = try? context.fetch(descriptor).first else { continue }
            switch change.op {
            case .done:
                ItemActions.complete(item, now: now)
            case .move:
                guard let due = change.due else { continue }
                item.dueAt = due
                item.timeGiven = change.timeGiven
                item.isDone = false
                item.doneAt = nil
            case .delete:
                guard allowDelete else { continue }
                PhotoStore.deleteItem(item, context: context)
            case .edit:
                if let title = change.title, !title.isEmpty {
                    item.title = title
                }
                if let body = change.body {
                    item.body = body
                }
            case .folder:
                guard item.kind != .reminder, let folder = change.folder else { continue }
                item.folderID = folder.uid
            }
            applied.append(change)
        }
        if !applied.isEmpty {
            try? context.save()
        }
        return applied
    }

    /// Сохраняет отмеченные карточки как записи. «В новую папку X» — создаёт папку наверху
    /// (одну на все карточки; такая уже есть — кладёт в неё).
    /// Возвращает, какая карточка (id) стала какой записью (uid) — чтобы прикрепить к ней фото.
    @MainActor
    @discardableResult
    static func save(_ drafts: [AIDraft], phrase: String, source: ItemSource = .ai,
                     context: ModelContext) -> [UUID: UUID] {
        var created: [String: UUID] = [:]
        var saved: [UUID: UUID] = [:]
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
                source: source,
                folderID: draft.folderID
            )
            if draft.kind != .reminder, item.folderID == nil, let name = draft.newFolder {
                let key = FolderTree.normalize(name)
                if let id = created[key] {
                    item.folderID = id
                } else {
                    let id = folderForNew(name, context: context)
                    created[key] = id
                    item.folderID = id
                }
            }
            context.insert(item)
            saved[draft.id] = item.uid
        }
        try? context.save()
        return saved
    }

    /// Папка наверху с таким именем: есть — она, нет — новая.
    @MainActor
    private static func folderForNew(_ name: String, context: ModelContext) -> UUID {
        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        let nodes = folders.map(\.node)
        let key = FolderTree.normalize(name)
        if let same = FolderTree.children(of: nil, in: nodes).first(where: { FolderTree.normalize($0.name) == key }) {
            return same.id
        }
        let folder = Folder(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            sortIndex: (folders.map(\.sortIndex).max() ?? -1) + 1)
        context.insert(folder)
        return folder.uid
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
        let known = AIService.knownItems(context)
        let folders = AIService.knownFolders(context)
        let jobs = entries
            .filter { $0.parsedJSON == nil && (retryFailed || $0.lastError == nil) }
            .map { (id: $0.uid, text: $0.text, said: $0.createdAt) }

        for job in jobs {
            do {
                let content = try await AIService.ask(job.text, said: job.said, known: known, folders: folders)
                _ = try AIService.parse(content, said: job.said, known: known, folders: folders)
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

extension AIKnownItem {
    init(item: Item) {
        self.init(uid: item.uid, kind: item.kind, title: item.title,
                  due: item.kind == .reminder ? item.dueAt : nil, timeGiven: item.timeGiven,
                  repeatRule: item.repeatRule, createdAt: item.createdAt)
    }
}
