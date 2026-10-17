import Foundation

/// 8 контрольных фраз этапа 2 из плана. Разбираются так, будто сейчас пятница 16.10.2026, 22:24 по Москве.
enum AIControlCheck {
    struct Expected {
        let kind: ItemKind
        /// «2026-10-17 09:00» по Москве.
        var due: String? = nil
        var before: Int? = nil
        var repeatRule: RepeatRule? = nil
    }

    struct Case: Identifiable {
        let phrase: String
        let expected: [Expected]
        /// Как в таблице плана: «Напоминание, сб 09:00».
        let summary: String
        var id: String { phrase }
    }

    struct Outcome {
        let passed: Bool
        let details: String
    }

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .current
        calendar.locale = Locale(identifier: "ru_RU")
        return calendar
    }()

    static let now: Date = date("2026-10-16 22:24") ?? Date()
    static let defaults = ParseDefaults(hour: 9, minute: 0, beforeMin: 15)

    static let cases: [Case] = [
        Case(phrase: "завтра подойти к учителю",
             expected: [Expected(kind: .reminder, due: "2026-10-17 09:00")],
             summary: "Напоминание, сб 09:00"),
        Case(phrase: "в пятницу после школы забрать кроссовки с почты",
             expected: [Expected(kind: .reminder, due: "2026-10-23 15:00")],
             summary: "Напоминание, следующая пт 15:00"),
        Case(phrase: "через 2 часа позвонить маме",
             expected: [Expected(kind: .reminder, due: "2026-10-17 00:24")],
             summary: "Напоминание, сб 00:24"),
        Case(phrase: "идея: бот, который сам считает прибыль с ресейла",
             expected: [Expected(kind: .idea)],
             summary: "Идея"),
        Case(phrase: "размер ноги: Nike 43, Adidas 42.5",
             expected: [Expected(kind: .note)],
             summary: "Заметка"),
        Case(phrase: "в 7 вечера оплатить сервер и завтра утром сдать пробник",
             expected: [Expected(kind: .reminder, due: "2026-10-17 19:00"),
                        Expected(kind: .reminder, due: "2026-10-17 09:00")],
             summary: "Два напоминания: сб 19:00 и сб 09:00"),
        Case(phrase: "в понедельник в 8:30 контрольная, напомни за час",
             expected: [Expected(kind: .reminder, due: "2026-10-19 08:30", before: 60)],
             summary: "Напоминание, пн 08:30, заранее 60 минут"),
        Case(phrase: "каждый вторник тренировка в 18:00",
             expected: [Expected(kind: .reminder, due: "2026-10-20 18:00", repeatRule: .weekly)],
             summary: "Напоминание с повтором по вторникам"),
    ]

    /// Спрашивает DeepSeek и сравнивает ответ с ожидаемым.
    static func run(_ check: Case, config: AIConfig) async -> Outcome {
        let system = AIPrompt.system(now: now, calendar: calendar, defaultHour: defaults.hour,
                                     defaultMinute: defaults.minute, defaultBefore: defaults.beforeMin)
        do {
            let content = try await DeepSeekClient.send(config: config, system: system, phrase: check.phrase)
            let result = try AIParser.parse(content, reference: now, now: now, defaults: defaults, calendar: calendar)
            let issues = problems(result.drafts, expected: check.expected)
            let got = result.drafts.map { describe($0) }.joined(separator: "; ")
            if issues.isEmpty {
                return Outcome(passed: true, details: got)
            }
            return Outcome(passed: false, details: "Получилось: \(got.isEmpty ? "ничего" : got). " + issues.joined(separator: "; "))
        } catch {
            return Outcome(passed: false, details: AIError.from(error).message)
        }
    }

    /// Чего не хватает в разборе. Пустой список — всё верно. Порядок записей не важен.
    static func problems(_ drafts: [AIDraft], expected: [Expected]) -> [String] {
        var issues: [String] = []
        if drafts.count != expected.count {
            issues.append("записей \(drafts.count), а надо \(expected.count)")
        }
        var left = drafts
        for item in expected {
            if let index = left.firstIndex(where: { matches($0, item) }) {
                left.remove(at: index)
            } else {
                issues.append("нет: \(describe(item))")
            }
        }
        return issues
    }

    static func matches(_ draft: AIDraft, _ item: Expected) -> Bool {
        guard draft.kind == item.kind else { return false }
        if let due = item.due {
            guard let actual = draft.due, text(actual) == due else { return false }
        }
        if let before = item.before, draft.remindBeforeMin != before { return false }
        if let rule = item.repeatRule, draft.repeatRule != rule { return false }
        return true
    }

    /// «Напоминание, сб 17.10 09:00, за 60 мин, каждую неделю».
    static func describe(_ draft: AIDraft) -> String {
        var parts = [draft.kind.title]
        if let due = draft.due {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: "ru_RU")
            formatter.dateFormat = "EE d.MM HH:mm"
            parts.append(formatter.string(from: due))
        }
        if let before = draft.remindBeforeMin { parts.append("за \(before) мин") }
        if let rule = draft.repeatRule { parts.append(rule.title.lowercased()) }
        return parts.joined(separator: ", ")
    }

    static func describe(_ item: Expected) -> String {
        var parts = [item.kind.title]
        if let due = item.due { parts.append(due) }
        if let before = item.before { parts.append("за \(before) мин") }
        if let rule = item.repeatRule { parts.append(rule.title.lowercased()) }
        return parts.joined(separator: ", ")
    }

    static func date(_ text: String) -> Date? {
        formatter.date(from: text)
    }

    static func text(_ date: Date) -> String {
        formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
