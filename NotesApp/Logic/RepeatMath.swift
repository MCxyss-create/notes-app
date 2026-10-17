import Foundation

/// Повторы напоминаний: каждый день / неделю / месяц от даты дела.
enum RepeatMath {
    /// Повтор номер `index` от начальной даты (0 — сама начальная).
    /// Месяцы считаются от начальной даты: 31 января → 28 февраля → 31 марта.
    static func occurrence(_ start: Date, rule: RepeatRule, index: Int, calendar: Calendar = .current) -> Date? {
        switch rule {
        case .daily: return calendar.date(byAdding: .day, value: index, to: start)
        case .weekly: return calendar.date(byAdding: .day, value: 7 * index, to: start)
        case .monthly: return calendar.date(byAdding: .month, value: index, to: start)
        }
    }

    /// Ближайшие моменты дела строго после `now` и не позже `until`.
    /// Обычное дело — только его срок; повторяющееся — его повторы.
    static func upcoming(
        start: Date,
        rule: RepeatRule?,
        after now: Date,
        until: Date,
        limit: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        guard limit > 0 else { return [] }
        guard let rule else {
            return (start > now && start <= until) ? [start] : []
        }
        var result: [Date] = []
        var index = 0
        while result.count < limit, index < 20_000 {
            guard let date = occurrence(start, rule: rule, index: index, calendar: calendar) else { break }
            if date > until { break }
            if date > now { result.append(date) }
            index += 1
        }
        return result
    }

    /// Следующий раз после «Готово»: первый повтор позже текущего срока и позже «сейчас».
    static func next(after due: Date, rule: RepeatRule, now: Date, calendar: Calendar = .current) -> Date {
        let floor = max(due, now)
        var index = 1
        while index < 20_000 {
            if let date = occurrence(due, rule: rule, index: index, calendar: calendar), date > floor {
                return date
            }
            index += 1
        }
        return due
    }
}
