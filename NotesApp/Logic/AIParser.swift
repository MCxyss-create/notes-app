import Foundation

/// Значения по умолчанию из настроек: время для дня без часа и «напомнить заранее».
struct ParseDefaults: Equatable {
    var hour: Int
    var minute: Int
    var beforeMin: Int
}

/// Одна запись, как её понял ИИ. Ещё не сохранена — показывается на карточке.
struct AIDraft: Identifiable, Equatable {
    let id = UUID()
    var kind: ItemKind
    var title: String
    var body: String?
    var due: Date?
    var timeGiven: Bool
    var remindBeforeMin: Int?
    var repeatRule: RepeatRule?
    var tags: [String]
    /// Что приложение поправило за ИИ или что стоит проверить глазами.
    var warning: String?
    /// Сохранять ли эту карточку.
    var include = true
    /// Папка идеи или заметки (у дел — nil).
    var folderID: UUID? = nil
    /// «в новую папку X»: папку создаст сохранение, если такой ещё нет.
    var newFolder: String? = nil

    /// Фраза как есть — заметкой: первая строка — заголовок, остальное — подробности.
    static func note(from phrase: String) -> AIDraft {
        let parts = phrase.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
        let title = String(parts.first ?? "").trimmingCharacters(in: .whitespaces)
        let rest = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return AIDraft(kind: .note, title: title.isEmpty ? "Без названия" : title, body: rest.isEmpty ? nil : rest,
                       due: nil, timeGiven: true, remindBeforeMin: nil, repeatRule: nil, tags: [])
    }
}

struct AIResult {
    var reply: String
    var drafts: [AIDraft]
    /// Команды про уже сохранённые записи: «перенеси», «готово», «удали», «переименуй».
    var changes: [AIChange] = []
    /// Ответ на вопрос («что у меня завтра?»): о каких записях речь.
    var found: [AIKnownItem] = []
    /// Это был вопрос: записывать нечего, только показать ответ.
    var answered = false
}

/// Проверяет ответ DeepSeek, не принимая его на веру: формат JSON, пустые заголовки,
/// виды записей, даты в прошлом, «заранее» и повторы.
enum AIParser {
    static let maxBeforeMin = 7 * 24 * 60

    /// reference — когда фраза сказана (от него ИИ считал «завтра»), now — сейчас.
    /// Они различаются у фраз из «Входящих», разобранных позже.
    /// known — записи, которые уже есть: по ним разбираются команды и вопросы.
    static func parse(_ content: String, reference: Date, now: Date, defaults: ParseDefaults, calendar: Calendar,
                      known: [AIKnownItem] = [], folders: [AIKnownFolder] = []) throws -> AIResult {
        guard let root = jsonObject(content) else {
            throw AIError.badResponse("это не JSON")
        }
        guard root["items"] != nil || root["reply"] != nil || root["changes"] != nil || root["found"] != nil else {
            throw AIError.badResponse("нет списка записей")
        }
        let list = ((root["items"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }
        let drafts = list.compactMap { raw in
            draft(from: raw, reference: reference, now: now, defaults: defaults, calendar: calendar)
                .map { filed($0, raw: raw, folders: folders) }
        }
        let changes = self.changes(root["changes"], known: known, reference: reference, now: now,
                                   defaults: defaults, calendar: calendar, folders: folders)
        let found = self.found(root["found"], known: known)
        let answered = root["found"] is [Any] && drafts.isEmpty && changes.isEmpty
        return AIResult(reply: text(root["reply"]) ?? "", drafts: drafts, changes: changes,
                        found: found, answered: answered)
    }

    static func draft(from raw: [String: Any], reference: Date, now: Date, defaults: ParseDefaults, calendar: Calendar) -> AIDraft? {
        var title = text(raw["title"]) ?? ""
        var details = text(raw["body"])
        while title.hasSuffix(".") {
            title.removeLast()
        }
        title = title.trimmingCharacters(in: .whitespaces)
        if title.isEmpty, let source = details {
            // Пустой заголовок: берём первые слова подробностей.
            let words = source.split(whereSeparator: \.isWhitespace)
            title = words.prefix(6).joined(separator: " ")
            if words.count <= 6 { details = nil }
        }
        guard !title.isEmpty else { return nil }

        let tagList = tags(raw["tags"])
        let parsedDue = date(raw["due"], calendar: calendar)
        let kind = text(raw["kind"]).flatMap { ItemKind(rawValue: $0.lowercased()) }
            ?? (parsedDue != nil ? .reminder : .note)

        // Срок, «заранее» и повтор бывают только у напоминаний со сроком.
        guard kind == .reminder, let parsed = parsedDue else {
            return AIDraft(kind: kind, title: title, body: details, due: nil, timeGiven: true,
                           remindBeforeMin: nil, repeatRule: nil, tags: tagList)
        }

        var due = parsed.date
        var timeGiven = bool(raw["time_given"]) ?? !parsed.dayOnly
        if parsed.dayOnly {
            due = DateMath.atTime(due, hour: defaults.hour, minute: defaults.minute, calendar: calendar)
            timeGiven = false
        }
        let rule = text(raw["repeat"]).flatMap { RepeatRule(rawValue: $0.lowercased()) }
        let before = int(raw["remind_before_min"]) ?? defaults.beforeMin
        var warning: String?

        // Дата раньше момента, когда фраза сказана, — ИИ ошибся.
        if due < reference.addingTimeInterval(-60) {
            if let rule {
                due = nextTime(due, rule: rule, after: reference, calendar: calendar)
            } else if reference.timeIntervalSince(due) < 86_400 {
                due = calendar.date(byAdding: .day, value: 1, to: due) ?? due
                warning = "Это время уже прошло — перенёс на день вперёд"
            } else {
                warning = "Дата в прошлом — проверь"
            }
        }
        // Фраза из «Входящих» могла ждать сети дольше, чем до срока.
        if warning == nil, due < now.addingTimeInterval(-60) {
            warning = "Время уже прошло"
        }

        return AIDraft(kind: .reminder, title: title, body: details, due: due, timeGiven: timeGiven,
                       remindBeforeMin: before > 0 ? min(before, maxBeforeMin) : nil,
                       repeatRule: rule, tags: tagList, warning: warning)
    }

    /// Папка из ответа: "folder" — номер из списка, "folder_new" — имя новой папки.
    /// Дела в папки не кладутся; незнакомый номер — без папки. Новая папка с именем уже
    /// существующей — в существующую.
    static func filed(_ draft: AIDraft, raw: [String: Any], folders: [AIKnownFolder]) -> AIDraft {
        guard draft.kind != .reminder else { return draft }
        var result = draft
        if let folder = findFolder(raw["folder"], in: folders) {
            result.folderID = folder.uid
        } else if let name = text(raw["folder_new"]).map({ String($0.prefix(40)) }) {
            let key = FolderTree.normalize(name)
            let same = folders.filter { FolderTree.normalize($0.name) == key }
            if let existing = same.first(where: \.isTop) ?? same.first {
                result.folderID = existing.uid
            } else {
                result.newFolder = name
            }
        }
        return result
    }

    /// Ближайший повтор не раньше reference: каждый день / неделю / месяц от исходной даты.
    static func nextTime(_ start: Date, rule: RepeatRule, after reference: Date, calendar: Calendar) -> Date {
        for step in 1...1000 {
            let next: Date?
            switch rule {
            case .daily: next = calendar.date(byAdding: .day, value: step, to: start)
            case .weekly: next = calendar.date(byAdding: .day, value: 7 * step, to: start)
            case .monthly: next = calendar.date(byAdding: .month, value: step, to: start)
            }
            if let next, next >= reference { return next }
        }
        return start
    }

    /// JSON-объект из ответа. Модель иногда оборачивает его в ```json … ``` — берём от «{» до «}».
    static func jsonObject(_ content: String) -> [String: Any]? {
        guard let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"), start < end else {
            return nil
        }
        let data = Data(content[start...end].utf8)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Строка без пробелов по краям; пустая и "null" — nil.
    static func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.lowercased() == "null" ? nil : trimmed
    }

    static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = text(value) { return Int(string) }
        return nil
    }

    static func bool(_ value: Any?) -> Bool? {
        if let flag = value as? Bool { return flag }
        if let string = text(value)?.lowercased() { return string == "true" || string == "да" }
        return nil
    }

    /// До 3 тегов: строчными, без «#», без повторов. Принимает список или строку через запятую.
    static func tags(_ value: Any?) -> [String] {
        let raw: [String]
        if let list = value as? [Any] {
            raw = list.compactMap { $0 as? String }
        } else if let line = value as? String {
            raw = line.components(separatedBy: ",")
        } else {
            raw = []
        }
        let junk = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "#"))
        var result: [String] = []
        for tag in raw {
            let clean = tag.trimmingCharacters(in: junk).lowercased()
            guard !clean.isEmpty, clean.count <= 30, !result.contains(clean) else { continue }
            result.append(clean)
            if result.count == 3 { break }
        }
        return result
    }

    /// «2026-10-17T09:00:00+03:00», с долями секунд или «Z». Без пояса — пояс календаря.
    /// Только день («2026-10-17») — dayOnly: время подставит приложение.
    static func date(_ value: Any?, calendar: Calendar) -> (date: Date, dayOnly: Bool)? {
        guard let string = text(value) else { return nil }

        let iso = ISO8601DateFormatter()
        let variants: [ISO8601DateFormatter.Options] = [[.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds]]
        for options in variants {
            iso.formatOptions = options
            if let date = iso.date(from: string) { return (date, false) }
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for pattern in ["yyyy-MM-dd'T'HH:mmXXXXX", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: string) { return (date, false) }
        }
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: string) { return (date, true) }
        return nil
    }
}
