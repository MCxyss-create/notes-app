import Foundation

/// Настройки сводок: утром — что сегодня, вечером — что завтра.
struct SummarySettings: Equatable {
    var morningOn: Bool
    /// Минуты от полуночи: 480 = 08:00.
    var morningMinutes: Int
    var eveningOn: Bool
    /// Минуты от полуночи: 1260 = 21:00.
    var eveningMinutes: Int

    static let standard = SummarySettings(morningOn: true, morningMinutes: 8 * 60, eveningOn: true, eveningMinutes: 21 * 60)
}

/// Утренняя сводка и план на завтра. Текст собирается заранее, поэтому при любой правке
/// записей сводки пересобираются вместе с остальными уведомлениями.
enum SummaryPlanner {
    static let idPrefix = "summary-"
    /// На сколько дней вперёд ставить сводки (на случай, если приложение несколько дней не открывали).
    static let daysAhead = 3
    static let maxShown = 5

    struct Entry: Equatable {
        let date: Date
        let title: String
    }

    static func plan(
        _ reminders: [ReminderInput],
        now: Date,
        settings: SummarySettings,
        calendar: Calendar = .current
    ) -> [PlannedNotification] {
        var result: [PlannedNotification] = []
        let today = calendar.startOfDay(for: now)

        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }

            if settings.morningOn {
                let fire = time(on: day, minutes: settings.morningMinutes, calendar: calendar)
                if fire > now {
                    let list = entries(on: day, reminders: reminders, calendar: calendar)
                    // Просроченные известны только на сегодня: к другим дням их могут закрыть.
                    let overdue = offset == 0 ? overdueCount(reminders, before: today) : 0
                    if let note = morning(list, overdue: overdue, fire: fire, day: day, calendar: calendar) {
                        result.append(note)
                    }
                }
            }

            if settings.eveningOn, let nextDay = calendar.date(byAdding: .day, value: 1, to: day) {
                let fire = time(on: day, minutes: settings.eveningMinutes, calendar: calendar)
                let list = entries(on: nextDay, reminders: reminders, calendar: calendar)
                if fire > now, !list.isEmpty {
                    result.append(PlannedNotification(
                        id: "\(idPrefix)evening-\(dayKey(day, calendar: calendar))",
                        date: fire,
                        title: "Завтра \(countText(list.count))",
                        body: bodyText(list, calendar: calendar)
                    ))
                }
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    /// Дела (с повторами), которые приходятся на этот день, по времени.
    static func entries(on day: Date, reminders: [ReminderInput], calendar: Calendar) -> [Entry] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        var list: [Entry] = []
        for r in reminders where !r.isDone {
            guard let due = r.dueAt else { continue }
            let dates = RepeatMath.upcoming(
                start: due,
                rule: r.repeatRule,
                after: start.addingTimeInterval(-1),
                until: end.addingTimeInterval(-1),
                limit: 3,
                calendar: calendar
            )
            for date in dates where date >= start && date < end {
                list.append(Entry(date: date, title: r.title))
            }
        }
        return list.sorted { $0.date < $1.date }
    }

    static func overdueCount(_ reminders: [ReminderInput], before start: Date) -> Int {
        reminders.filter { !$0.isDone && ($0.dueAt.map { $0 < start } ?? false) }.count
    }

    static func countText(_ n: Int) -> String {
        "\(n) \(RussianPlural.pick(n, "дело", "дела", "дел"))"
    }

    /// «09:00 Подойти к учителю · 13:30 Сдать пробник · и ещё 2».
    static func bodyText(_ list: [Entry], calendar: Calendar) -> String {
        var parts = list.prefix(maxShown).map { "\(DateText.timeString($0.date, calendar: calendar)) \($0.title)" }
        if list.count > maxShown {
            parts.append("и ещё \(list.count - maxShown)")
        }
        return parts.joined(separator: " · ")
    }

    private static func morning(_ list: [Entry], overdue: Int, fire: Date, day: Date, calendar: Calendar) -> PlannedNotification? {
        guard !list.isEmpty || overdue > 0 else { return nil }
        let id = "\(idPrefix)morning-\(dayKey(day, calendar: calendar))"
        if list.isEmpty {
            return PlannedNotification(id: id, date: fire, title: "Есть просроченные дела",
                                       body: "Просрочено: \(overdue)")
        }
        var body = bodyText(list, calendar: calendar)
        if overdue > 0 {
            body += " · просрочено: \(overdue)"
        }
        return PlannedNotification(id: id, date: fire, title: "Сегодня \(countText(list.count))", body: body)
    }

    private static func time(on day: Date, minutes: Int, calendar: Calendar) -> Date {
        DateMath.atTime(day, hour: minutes / 60, minute: minutes % 60, calendar: calendar)
    }

    static func dayKey(_ day: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
