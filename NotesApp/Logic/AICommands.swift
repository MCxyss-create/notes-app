import Foundation

/// Запись, которая уже есть в приложении, — как её видит ИИ. ref — первые 6 знаков uid:
/// со временем не меняется, поэтому фраза из «Входящих» попадёт в ту же запись.
struct AIKnownItem: Identifiable, Equatable {
    let ref: String
    let uid: UUID
    let kind: ItemKind
    let title: String
    let due: Date?
    let timeGiven: Bool
    let repeatRule: RepeatRule?
    let createdAt: Date

    var id: UUID { uid }

    init(uid: UUID, kind: ItemKind, title: String, due: Date? = nil, timeGiven: Bool = true,
         repeatRule: RepeatRule? = nil, createdAt: Date = .distantPast) {
        self.ref = Self.ref(for: uid)
        self.uid = uid
        self.kind = kind
        self.title = title
        self.due = due
        self.timeGiven = timeGiven
        self.repeatRule = repeatRule
        self.createdAt = createdAt
    }

    static func ref(for uid: UUID) -> String {
        String(uid.uuidString.lowercased().filter { $0 != "-" }.prefix(6))
    }
}

/// Изменение уже сохранённой записи по команде («перенеси», «готово», «удали»).
/// Применяется только после кнопки на карточке.
struct AIChange: Identifiable, Equatable {
    enum Op: String, CaseIterable {
        case done
        case move
        case delete
        case edit

        var title: String {
            switch self {
            case .done: return "Готово"
            case .move: return "Перенести"
            case .delete: return "Удалить"
            case .edit: return "Изменить"
            }
        }

        /// Для ответа Siri: «Перенёс: Подойти к учителю».
        var pastTitle: String {
            switch self {
            case .done: return "Отметил"
            case .move: return "Перенёс"
            case .delete: return "Удалил"
            case .edit: return "Изменил"
            }
        }

        var symbol: String {
            switch self {
            case .done: return "checkmark.circle"
            case .move: return "calendar.badge.clock"
            case .delete: return "trash"
            case .edit: return "pencil"
            }
        }
    }

    let id = UUID()
    var op: Op
    var target: AIKnownItem
    var due: Date? = nil
    var timeGiven = true
    var title: String? = nil
    var body: String? = nil
    var warning: String? = nil
    var include = true
}

/// Какие записи показать ИИ, чтобы он понимал команды.
enum AIContext {
    static let reminderLimit = 40
    static let otherLimit = 20

    /// Несделанные дела: ближайшие сначала, без срока — в конце. Потом свежие идеи и заметки.
    static func forPrompt(_ known: [AIKnownItem]) -> [AIKnownItem] {
        let reminders = known.filter { $0.kind == .reminder }.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return a.createdAt > b.createdAt
            }
        }
        let others = known.filter { $0.kind != .reminder }.sorted { $0.createdAt > $1.createdAt }
        return Array(reminders.prefix(reminderLimit)) + Array(others.prefix(otherLimit))
    }

    /// «- a1b2c3 | дело | Подойти к учителю | 2026-10-17 09:00 | каждый день»
    static func line(_ item: AIKnownItem, calendar: Calendar) -> String {
        var parts = [item.ref, word(item.kind), item.title]
        if let due = item.due {
            parts.append(AIPrompt.format(due, "yyyy-MM-dd HH:mm", calendar))
        }
        if let rule = item.repeatRule {
            parts.append(rule.title.lowercased())
        }
        return "- " + parts.joined(separator: " | ")
    }

    static func word(_ kind: ItemKind) -> String {
        switch kind {
        case .reminder: return "дело"
        case .idea: return "идея"
        case .note: return "заметка"
        }
    }
}

/// Разбор команд из ответа DeepSeek: "changes" и "found". Номера, которых нет в списке, — мимо.
extension AIParser {
    static func changes(_ value: Any?, known: [AIKnownItem], reference: Date, now: Date,
                        defaults: ParseDefaults, calendar: Calendar) -> [AIChange] {
        let list = ((value as? [Any]) ?? []).compactMap { $0 as? [String: Any] }
        var result: [AIChange] = []
        for raw in list {
            guard let op = op(raw["op"]), let target = find(raw["id"], in: known) else { continue }
            if result.contains(where: { $0.target.uid == target.uid && $0.op == op }) { continue }
            var change = AIChange(op: op, target: target)
            switch op {
            case .done, .delete:
                break
            case .move:
                guard target.kind == .reminder,
                      let moved = movedDue(raw, target: target, reference: reference, now: now,
                                           defaults: defaults, calendar: calendar) else { continue }
                change.due = moved.due
                change.timeGiven = moved.timeGiven
                change.warning = moved.warning
            case .edit:
                var newTitle = text(raw["title"])
                while newTitle?.hasSuffix(".") == true {
                    newTitle?.removeLast()
                }
                if newTitle == target.title { newTitle = nil }
                let newBody = text(raw["body"])
                guard newTitle != nil || newBody != nil else { continue }
                change.title = newTitle
                change.body = newBody
            }
            result.append(change)
        }
        return result
    }

    /// Ответ на вопрос («что у меня завтра?»): записи, о которых речь, в том же порядке.
    static func found(_ value: Any?, known: [AIKnownItem]) -> [AIKnownItem] {
        guard let list = value as? [Any] else { return [] }
        var result: [AIKnownItem] = []
        for entry in list {
            guard let item = find(entry, in: known), !result.contains(item) else { continue }
            result.append(item)
        }
        return result
    }

    static func op(_ value: Any?) -> AIChange.Op? {
        guard let raw = text(value)?.lowercased() else { return nil }
        switch raw {
        case "done", "complete", "completed", "finish", "check": return .done
        case "move", "reschedule", "snooze", "postpone", "shift": return .move
        case "delete", "remove": return .delete
        case "edit", "rename", "update", "append": return .edit
        default: return nil
        }
    }

    /// Номер записи: «a1b2c3», «#a1b2c3», полный uid или {"id": …}.
    static func find(_ value: Any?, in known: [AIKnownItem]) -> AIKnownItem? {
        if let object = value as? [String: Any] {
            return find(object["id"], in: known)
        }
        let raw: String?
        if let number = value as? NSNumber {
            raw = number.stringValue
        } else {
            raw = text(value)
        }
        guard var key = raw?.lowercased() else { return nil }
        key = key.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        key = key.filter { $0 != "-" }
        guard key.count >= 4 else { return nil }
        return known.first { $0.ref == key } ?? known.first { key.hasPrefix($0.ref) }
    }

    /// Новый срок для «перенеси». Назван только день — остаётся прежнее время записи.
    static func movedDue(_ raw: [String: Any], target: AIKnownItem, reference: Date, now: Date,
                         defaults: ParseDefaults, calendar: Calendar) -> (due: Date, timeGiven: Bool, warning: String?)? {
        guard let parsed = date(raw["due"], calendar: calendar) else { return nil }
        var due = parsed.date
        var timeGiven = bool(raw["time_given"]) ?? !parsed.dayOnly
        if parsed.dayOnly {
            if let old = target.due {
                let time = calendar.dateComponents([.hour, .minute], from: old)
                due = DateMath.atTime(due, hour: time.hour ?? defaults.hour, minute: time.minute ?? defaults.minute,
                                      calendar: calendar)
                timeGiven = target.timeGiven
            } else {
                due = DateMath.atTime(due, hour: defaults.hour, minute: defaults.minute, calendar: calendar)
                timeGiven = false
            }
        }
        var warning: String?
        if due < reference.addingTimeInterval(-60) {
            if reference.timeIntervalSince(due) < 86_400 {
                due = calendar.date(byAdding: .day, value: 1, to: due) ?? due
                warning = "Это время уже прошло — перенёс на день вперёд"
            } else {
                warning = "Дата в прошлом — проверь"
            }
        }
        if warning == nil, due < now.addingTimeInterval(-60) {
            warning = "Время уже прошло"
        }
        return (due, timeGiven, warning)
    }
}
