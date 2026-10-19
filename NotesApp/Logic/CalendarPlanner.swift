import Foundation

/// Уведомления о днях рождения, годовщинах и (если включено) праздниках: на 35 дней вперёд,
/// по «Напомнить» каждого события, не больше 8 ближайших.
/// Имя не склоняем («у Лёши» из «Лёша» правильно не собрать), поэтому «день рождения: Лёша».
enum CalendarPlanner {
    static let idPrefix = "event-"
    /// Из 64 мест iOS: дела 48, календарь 8, сводки до 6, переподпись 1, проверочное 1.
    static let limit = 8
    static let horizonDays = 35

    /// defaultMinutes — время напоминания, если у события своё не задано (минуты от полуночи).
    static func plan(_ entries: [CalendarEntry], now: Date, defaultMinutes: Int, limit: Int = limit,
                     calendar: Calendar = .current) -> [PlannedNotification] {
        guard let end = calendar.date(byAdding: .day, value: horizonDays, to: now) else { return [] }
        var result: [PlannedNotification] = []
        for entry in entries {
            guard let date = CalendarMath.next(entry, from: now, calendar: calendar) else { continue }
            let minutes = entry.remindMinutes ?? defaultMinutes
            let years = CalendarMath.years(entry, on: date, calendar: calendar)
            for before in Set(entry.remindDays).sorted() where before >= 0 {
                guard let day = calendar.date(byAdding: .day, value: -before, to: date) else { continue }
                let fire = DateMath.atTime(day, hour: minutes / 60, minute: minutes % 60, calendar: calendar)
                guard fire > now, fire <= end else { continue }
                result.append(PlannedNotification(
                    id: "\(idPrefix)\(entry.id)-\(before)-\(SummaryPlanner.dayKey(date, calendar: calendar))",
                    date: fire,
                    title: title(entry, before: before, years: years),
                    body: body(entry, before: before, years: years)
                ))
            }
        }
        return Array(result.sorted { $0.date < $1.date }.prefix(limit))
    }

    /// «🎂 Сегодня день рождения: Лёша — 18 лет», «Завтра день рождения: Лёша»,
    /// «🎉 Сегодня: День народного единства», «Через неделю: Годовщина свадьбы».
    static func title(_ entry: CalendarEntry, before: Int, years: Int?) -> String {
        let when = whenWord(before)
        switch entry.type {
        case .birthday:
            var line = "\(when) день рождения: \(entry.title)"
            if before == 0, let age = CalendarMath.ageText(.birthday, years: years, isToday: true) {
                line += " — \(age)"
            }
            return before == 0 ? "🎂 \(line)" : line
        case .holiday:
            return before == 0 ? "🎉 \(when): \(entry.title)" : "\(when): \(entry.title)"
        case .anniversary, .other:
            var line = "\(when): \(entry.title)"
            if before == 0, let age = CalendarMath.ageText(entry.type, years: years, isToday: true) {
                line += " — \(age)"
            }
            return line
        }
    }

    /// Заранее — дата и возраст: «12 марта · исполнится 18». В сам день ДР — «Не забудь поздравить».
    static func body(_ entry: CalendarEntry, before: Int, years: Int?) -> String {
        guard before > 0 else {
            return entry.type == .birthday ? "Не забудь поздравить" : ""
        }
        var parts = [CalendarMath.dayMonthText(month: entry.month, day: entry.day)]
        if let age = CalendarMath.ageText(entry.type, years: years, isToday: false) {
            parts.append(age)
        }
        return parts.joined(separator: " · ")
    }

    /// 0 — «Сегодня», 1 — «Завтра», 7 — «Через неделю», иначе «Через 3 дня».
    static func whenWord(_ before: Int) -> String {
        switch before {
        case 0: return "Сегодня"
        case 1: return "Завтра"
        case 7: return "Через неделю"
        default: return "Через \(before) \(RussianPlural.pick(before, "день", "дня", "дней"))"
        }
    }
}
