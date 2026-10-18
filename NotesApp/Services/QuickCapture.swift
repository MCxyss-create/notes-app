import Foundation
import SwiftData

/// Что сделать, когда приложение открыла команда (например, Кнопка действия → «Надиктовать»).
@MainActor
final class QuickLaunch: ObservableObject {
    static let shared = QuickLaunch()

    enum Action: Equatable {
        case dictate
        case type
        /// Приложение снова открыли — слушать, если поле пустое и ничего не открыто.
        case listen
    }

    @Published var pending: Action?

    func request(_ action: Action) {
        pending = action
    }

    /// Забрать действие один раз.
    func take() -> Action? {
        let action = pending
        pending = nil
        return action
    }
}

/// Запись без открытия приложения: Siri, Кнопка действия, Быстрые команды.
@MainActor
enum QuickCapture {
    /// С ✨ фразу разбирает DeepSeek и записи сохраняются сразу, без карточек.
    /// Не вышло (нет сети, ключа, долго) — фраза ложится во «Входящие» и разберётся в приложении.
    static func save(_ raw: String, now: Date = Date()) async -> String {
        let phrase = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return "Пусто — нечего записывать." }

        let context = AppModel.sharedContainer().mainContext
        let aiOn = UserDefaults.standard.object(forKey: SettingsKeys.aiEnabled) as? Bool ?? true

        guard aiOn else {
            let note = AIDraft.note(from: phrase)
            AIService.save([note], phrase: phrase, source: .manual, context: context)
            await rescheduleAll(context)
            return QuickCaptureText.saved([note], reply: "", now: now)
        }

        do {
            let known = AIService.knownItems(context)
            let content = try await askWithTimeout(phrase, said: now, known: known)
            let result = try AIService.parse(content, said: now, known: known)
            // Команда или вопрос: «маме позвонил», «что у меня завтра?» — заметку не создаём.
            if result.drafts.isEmpty && (!result.changes.isEmpty || result.answered) {
                let applied = AIService.apply(result.changes, context: context, now: now, allowDelete: false)
                await rescheduleAll(context)
                let skippedDelete = result.changes.contains { $0.op == .delete }
                return QuickCaptureText.changed(applied, skippedDelete: skippedDelete, reply: result.reply, now: now)
            }
            let drafts = result.drafts.isEmpty ? [AIDraft.note(from: phrase)] : result.drafts
            AIService.save(drafts, phrase: phrase, context: context)
            AIService.apply(result.changes, context: context, now: now, allowDelete: false)
            await rescheduleAll(context)
            return QuickCaptureText.saved(drafts, reply: result.reply, now: now)
        } catch {
            let problem = AIError.from(error)
            let entry = InboxEntry(text: phrase, createdAt: now)
            if !problem.isTemporary && problem != .noKey {
                entry.lastError = problem.message
            }
            context.insert(entry)
            try? context.save()
            return "Сохранил во «Входящие»: \(problem.message.lowercasedFirst). Разберу, когда откроешь «Мысли»."
        }
    }

    /// «Что сегодня?» — дела на сегодня с повторами и сколько просрочено с прошлых дней.
    static func todayText(now: Date = Date()) -> String {
        let context = AppModel.sharedContainer().mainContext
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        let reminders = items.filter { $0.kind == .reminder }.map { ReminderInput(item: $0) }
        let calendar = Calendar.current
        let entries = SummaryPlanner.entries(on: now, reminders: reminders, calendar: calendar)
        let overdue = SummaryPlanner.overdueCount(reminders, before: calendar.startOfDay(for: now))
        return QuickCaptureText.today(entries, overdue: overdue, calendar: calendar)
    }

    /// Siri долго не ждёт: если DeepSeek не ответил за 20 секунд — во «Входящие».
    private static func askWithTimeout(_ phrase: String, said: Date, known: [AIKnownItem]) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await AIService.ask(phrase, said: said, known: known)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 20_000_000_000)
                throw URLError(.timedOut)
            }
            guard let first = try await group.next() else {
                throw URLError(.timedOut)
            }
            group.cancelAll()
            return first
        }
    }

    private static func rescheduleAll(_ context: ModelContext) async {
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        await NotificationScheduler.rescheduleAll(items: items).value
    }
}
