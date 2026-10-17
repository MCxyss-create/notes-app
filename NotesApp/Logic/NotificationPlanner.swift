import Foundation

/// Данные напоминания, нужные для планирования уведомлений.
struct ReminderInput {
    let id: UUID
    let title: String
    let details: String?
    let dueAt: Date?
    let remindBeforeMin: Int?
    let isDone: Bool
    var repeatRule: RepeatRule? = nil
}

/// Одно уведомление, которое надо поставить в iOS.
struct PlannedNotification: Equatable {
    let id: String
    let date: Date
    let title: String
    let body: String
    /// Запись, к которой относится уведомление: по ней работают кнопки «Готово / Через час / Завтра».
    var itemID: UUID? = nil
    /// У повторяющегося дела в уведомлении только «Готово» (отложить нельзя — сдвинется весь повтор).
    var repeating: Bool = false
}

enum NotificationPlanner {
    /// iOS хранит до 64 запланированных уведомлений: 56 — делам,
    /// до 6 — сводкам, 1 — напоминанию о переподписи, 1 — проверочному.
    static let defaultLimit = 56
    static let idPrefix = "item-"
    /// Все уведомления, которые приложение пересчитывает само (проверочное сюда не входит).
    static let managedPrefixes = [idPrefix, SummaryPlanner.idPrefix, "resign-"]
    /// Повторяющееся дело: не дальше 35 дней и не больше 8 раз вперёд.
    static let repeatHorizonDays = 35
    static let perItemLimit = 8

    /// Ближайшие уведомления по времени: точное и «заранее», у повторяющихся — на каждый повтор.
    static func plan(
        _ reminders: [ReminderInput],
        now: Date,
        limit: Int = defaultLimit,
        calendar: Calendar = .current
    ) -> [PlannedNotification] {
        let horizon = now.addingTimeInterval(TimeInterval(repeatHorizonDays * 86_400))
        var result: [PlannedNotification] = []
        for r in reminders where !r.isDone {
            guard let due = r.dueAt else { continue }
            let details = r.details?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let dates = RepeatMath.upcoming(
                start: due,
                rule: r.repeatRule,
                after: now,
                until: r.repeatRule == nil ? .distantFuture : horizon,
                limit: perItemLimit,
                calendar: calendar
            )

            for date in dates {
                let stamp = Int(date.timeIntervalSince1970)
                result.append(PlannedNotification(
                    id: "\(idPrefix)\(r.id.uuidString)-due-\(stamp)",
                    date: date,
                    title: r.title,
                    body: details.isEmpty ? "Пора!" : details,
                    itemID: r.id,
                    repeating: r.repeatRule != nil
                ))

                if let before = r.remindBeforeMin, before > 0 {
                    let early = date.addingTimeInterval(TimeInterval(-before * 60))
                    if early > now {
                        result.append(PlannedNotification(
                            id: "\(idPrefix)\(r.id.uuidString)-before-\(stamp)",
                            date: early,
                            title: r.title,
                            body: beforeText(before),
                            itemID: r.id,
                            repeating: r.repeatRule != nil
                        ))
                    }
                }
            }
        }
        result.sort { $0.date < $1.date }
        return Array(result.prefix(limit))
    }

    /// «Через 15 минут», «Через час», «Через 2 часа».
    static func beforeText(_ minutes: Int) -> String {
        if minutes % 60 == 0 {
            let hours = minutes / 60
            if hours == 1 { return "Через час" }
            return "Через \(hours) \(RussianPlural.pick(hours, "час", "часа", "часов"))"
        }
        return "Через \(minutes) \(RussianPlural.pick(minutes, "минуту", "минуты", "минут"))"
    }
}

enum RussianPlural {
    /// pick(1, "минуту", "минуты", "минут") → «минуту»; 3 → «минуты»; 11 → «минут».
    static func pick(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n10 = n % 10
        let n100 = n % 100
        if n10 == 1 && n100 != 11 { return one }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return few }
        return many
    }
}

/// Варианты «напомнить заранее» для настроек и редактирования.
struct BeforeOption: Hashable {
    let minutes: Int
    let title: String

    static let all: [BeforeOption] = [
        BeforeOption(minutes: 0, title: "Не надо"),
        BeforeOption(minutes: 5, title: "За 5 минут"),
        BeforeOption(minutes: 15, title: "За 15 минут"),
        BeforeOption(minutes: 30, title: "За 30 минут"),
        BeforeOption(minutes: 60, title: "За час"),
        BeforeOption(minutes: 120, title: "За 2 часа"),
    ]
}
