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

    // MARK: - 4 контрольные команды про уже сохранённые записи

    struct ExpectedChange {
        let op: AIChange.Op
        let ref: String
        /// «2026-10-19 09:00» по Москве — для «перенеси».
        var due: String? = nil
    }

    struct CommandCase: Identifiable {
        let phrase: String
        var changes: [ExpectedChange] = []
        /// id записей в ответе на вопрос; nil — это не вопрос.
        var found: [String]? = nil
        let summary: String
        var id: String { phrase }
    }

    /// Какие записи «уже есть» для команд.
    static let commandItems: [AIKnownItem] = [
        AIKnownItem(uid: uid("A1B2C3D4-0000-4000-8000-000000000001"), kind: .reminder, title: "Подойти к учителю",
                    due: date("2026-10-17 09:00"), timeGiven: false),
        AIKnownItem(uid: uid("D4E5F6A7-0000-4000-8000-000000000002"), kind: .reminder, title: "Позвонить маме",
                    due: date("2026-10-17 18:00")),
        AIKnownItem(uid: uid("0C9D8E7F-0000-4000-8000-000000000003"), kind: .reminder, title: "Сдать пробник",
                    due: date("2026-10-19 13:30")),
        AIKnownItem(uid: uid("7F6E5D4C-0000-4000-8000-000000000004"), kind: .note, title: "Размер ноги: Nike 43, Adidas 42.5"),
        AIKnownItem(uid: uid("B7C8D9E0-0000-4000-8000-000000000005"), kind: .idea, title: "Бот для прибыли с ресейла"),
    ]

    static let commandCases: [CommandCase] = [
        CommandCase(phrase: "перенеси учителя на понедельник",
                    changes: [ExpectedChange(op: .move, ref: "a1b2c3", due: "2026-10-19 09:00")],
                    summary: "Перенести «Подойти к учителю» на пн 09:00"),
        CommandCase(phrase: "маме позвонил",
                    changes: [ExpectedChange(op: .done, ref: "d4e5f6")],
                    summary: "Готово: «Позвонить маме»"),
        CommandCase(phrase: "удали заметку про размер ноги",
                    changes: [ExpectedChange(op: .delete, ref: "7f6e5d")],
                    summary: "Удалить заметку «Размер ноги»"),
        CommandCase(phrase: "что у меня завтра?",
                    found: ["a1b2c3", "d4e5f6"],
                    summary: "Нашёл 2 дела на завтра, ничего не записал"),
    ]

    // MARK: - 2 контрольные фразы про календарь

    struct EventCase: Identifiable {
        let phrase: String
        let type: EventType
        let month: Int
        let day: Int
        let year: Int?
        let summary: String
        var id: String { phrase }
    }

    static let eventCases: [EventCase] = [
        EventCase(phrase: "у Лёши день рождения 12 марта", type: .birthday, month: 3, day: 12, year: nil,
                  summary: "День рождения 12.03, без года, не дело"),
        EventCase(phrase: "годовщина родителей 5 июня 1999", type: .anniversary, month: 6, day: 5, year: 1999,
                  summary: "Годовщина 05.06.1999, не дело"),
    ]

    static func run(_ check: EventCase, config: AIConfig) async -> Outcome {
        let system = AIPrompt.system(now: now, calendar: calendar, defaultHour: defaults.hour,
                                     defaultMinute: defaults.minute, defaultBefore: defaults.beforeMin)
        do {
            let content = try await DeepSeekClient.send(config: config, system: system, phrase: check.phrase)
            let result = try AIParser.parse(content, reference: now, now: now, defaults: defaults, calendar: calendar)
            let issues = problems(result, expected: check)
            let got = describeEvents(result)
            if issues.isEmpty {
                return Outcome(passed: true, details: got)
            }
            return Outcome(passed: false, details: "Получилось: \(got). " + issues.joined(separator: "; "))
        } catch {
            return Outcome(passed: false, details: AIError.from(error).message)
        }
    }

    /// Ровно одно событие нужного вида и даты; дел (reminder) не создано.
    static func problems(_ result: AIResult, expected: EventCase) -> [String] {
        var issues: [String] = []
        if result.events.count != 1 {
            issues.append("событий \(result.events.count), а надо 1")
        }
        if !result.events.contains(where: { $0.type == expected.type && $0.month == expected.month
            && $0.day == expected.day && $0.year == expected.year }) {
            issues.append("нет: \(expected.type.title.lowercased()) \(expected.day).\(expected.month)"
                          + (expected.year.map { ".\($0)" } ?? ""))
        }
        if result.drafts.contains(where: { $0.kind == .reminder }) {
            issues.append("создал дело вместо события")
        }
        return issues
    }

    /// «День рождения «Лёша» 12.3; новая: Напоминание».
    static func describeEvents(_ result: AIResult) -> String {
        var parts = result.events.map { event in
            "\(event.type.title) «\(event.title)» \(event.day).\(event.month)" + (event.year.map { ".\($0)" } ?? "")
        }
        parts += result.drafts.map { "новая: " + describe($0) }
        return parts.isEmpty ? "ничего" : parts.joined(separator: "; ")
    }

    // MARK: - 2 контрольные фразы про папки

    struct FolderCase: Identifiable {
        let phrase: String
        /// Новая запись этого вида — в папку folderRef.
        var draftKind: ItemKind? = nil
        /// Изменение «В папку»: какая запись (ref) и куда.
        var changeRef: String? = nil
        let folderRef: String
        let summary: String
        var id: String { phrase }
    }

    /// Какие папки «уже есть»: Проекты → VPN, Шопинг, Школа.
    static let folderItems: [AIKnownFolder] = [
        AIKnownFolder(uid: uid("F1A2B3C4-0000-4000-8000-000000000011"), name: "Проекты"),
        AIKnownFolder(uid: uid("E2B3C4D5-0000-4000-8000-000000000012"), name: "VPN", path: "Проекты / VPN"),
        AIKnownFolder(uid: uid("C3D4E5F6-0000-4000-8000-000000000013"), name: "Шопинг"),
        AIKnownFolder(uid: uid("A4B5C6D7-0000-4000-8000-000000000014"), name: "Школа"),
    ]

    static let folderCases: [FolderCase] = [
        FolderCase(phrase: "идея для VPN: реклама у блогеров",
                   draftKind: .idea, folderRef: "e2b3c4",
                   summary: "Идея в папке «Проекты / VPN»"),
        FolderCase(phrase: "перенеси заметку про размер ноги в папку Шопинг",
                   changeRef: "7f6e5d", folderRef: "c3d4e5",
                   summary: "Заметка «Размер ноги» — в папку «Шопинг»"),
    ]

    static func run(_ check: FolderCase, config: AIConfig) async -> Outcome {
        let system = AIPrompt.system(now: now, calendar: calendar, defaultHour: defaults.hour,
                                     defaultMinute: defaults.minute, defaultBefore: defaults.beforeMin,
                                     known: commandItems, folders: folderItems)
        do {
            let content = try await DeepSeekClient.send(config: config, system: system, phrase: check.phrase)
            let result = try AIParser.parse(content, reference: now, now: now, defaults: defaults,
                                            calendar: calendar, known: commandItems, folders: folderItems)
            let issues = problems(result, expected: check)
            let got = describeFolders(result)
            if issues.isEmpty {
                return Outcome(passed: true, details: got)
            }
            return Outcome(passed: false, details: "Получилось: \(got). " + issues.joined(separator: "; "))
        } catch {
            return Outcome(passed: false, details: AIError.from(error).message)
        }
    }

    /// Новая запись — нужного вида и в нужной папке; команда — «В папку» нужной записи в нужную папку.
    static func problems(_ result: AIResult, expected: FolderCase) -> [String] {
        let folder = folderItems.first { $0.ref == expected.folderRef }
        var issues: [String] = []
        if let kind = expected.draftKind {
            if !result.drafts.contains(where: { $0.kind == kind && $0.folderID == folder?.uid }) {
                issues.append("нет: \(kind.title.lowercased()) в папке «\(folder?.path ?? expected.folderRef)»")
            }
        }
        if let ref = expected.changeRef {
            if !result.drafts.isEmpty {
                issues.append("создал новые записи: \(result.drafts.count)")
            }
            if !result.changes.contains(where: { $0.op == .folder && $0.target.ref == ref && $0.folder?.uid == folder?.uid }) {
                issues.append("нет: в папку «\(folder?.path ?? expected.folderRef)» запись \(ref)")
            }
        }
        return issues
    }

    /// «Идея «Реклама у блогеров» → Проекты / VPN; В папку «Размер ноги» → Шопинг».
    static func describeFolders(_ result: AIResult) -> String {
        var parts = result.drafts.map { draft -> String in
            let path = folderItems.first { $0.uid == draft.folderID }?.path ?? draft.newFolder.map { "новая «\($0)»" }
            return "\(draft.kind.title) «\(draft.title)» → \(path ?? "без папки")"
        }
        parts += result.changes.map { change in
            "\(change.op.title) «\(change.target.title)»" + (change.folder.map { " → \($0.path)" } ?? "")
        }
        return parts.isEmpty ? "ничего" : parts.joined(separator: "; ")
    }

    static func run(_ check: CommandCase, config: AIConfig) async -> Outcome {
        let system = AIPrompt.system(now: now, calendar: calendar, defaultHour: defaults.hour,
                                     defaultMinute: defaults.minute, defaultBefore: defaults.beforeMin,
                                     known: commandItems)
        do {
            let content = try await DeepSeekClient.send(config: config, system: system, phrase: check.phrase)
            let result = try AIParser.parse(content, reference: now, now: now, defaults: defaults,
                                            calendar: calendar, known: commandItems)
            let issues = problems(result, expected: check)
            let got = describe(result)
            if issues.isEmpty {
                return Outcome(passed: true, details: got)
            }
            return Outcome(passed: false, details: "Получилось: \(got). " + issues.joined(separator: "; "))
        } catch {
            return Outcome(passed: false, details: AIError.from(error).message)
        }
    }

    /// Команда не должна создавать новых записей; изменения и найденное — как ожидалось.
    static func problems(_ result: AIResult, expected: CommandCase) -> [String] {
        var issues: [String] = []
        if !result.drafts.isEmpty {
            issues.append("создал новые записи: \(result.drafts.count)")
        }
        if result.changes.count != expected.changes.count {
            issues.append("изменений \(result.changes.count), а надо \(expected.changes.count)")
        }
        for item in expected.changes {
            let ok = result.changes.contains { change in
                guard change.op == item.op, change.target.ref == item.ref else { return false }
                guard let due = item.due else { return true }
                return change.due.map(text) == due
            }
            if !ok {
                issues.append("нет: \(item.op.title.lowercased()) \(item.ref)\(item.due.map { " → \($0)" } ?? "")")
            }
        }
        if let found = expected.found, Set(result.found.map(\.ref)) != Set(found) {
            issues.append("нашёл не те записи")
        }
        return issues
    }

    /// «Перенести Подойти к учителю → пн 19.10 09:00; нашёл: Позвонить маме».
    static func describe(_ result: AIResult) -> String {
        var parts = result.changes.map { change -> String in
            var line = "\(change.op.title) «\(change.target.title)»"
            if let due = change.due {
                line += " → " + dayTime(due)
            }
            return line
        }
        if !result.found.isEmpty {
            parts.append("нашёл: " + result.found.map(\.title).joined(separator: ", "))
        }
        parts += result.drafts.map { "новая: " + describe($0) }
        return parts.isEmpty ? "ничего" : parts.joined(separator: "; ")
    }

    /// «сб 17.10 09:00».
    static func dayTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EE d.MM HH:mm"
        return formatter.string(from: date)
    }

    private static func uid(_ text: String) -> UUID {
        UUID(uuidString: text) ?? UUID()
    }

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
