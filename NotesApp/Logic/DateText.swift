import Foundation

/// Даты по-человечески: «Сегодня, 09:00», «Завтра, 15:30», «пт, 23 окт., 15:00».
enum DateText {
    static let russian = Locale(identifier: "ru_RU")

    static func short(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = timeString(date, calendar: calendar)
        if calendar.isDate(date, inSameDayAs: now) {
            return "Сегодня, \(time)"
        }
        if let next = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: next) {
            return "Завтра, \(time)"
        }
        if let prev = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: prev) {
            return "Вчера, \(time)"
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        var style = Date.FormatStyle(locale: russian, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.abbreviated)
            .day()
            .month(.abbreviated)
        if !sameYear {
            style = style.year()
        }
        return "\(date.formatted(style)), \(time)"
    }

    static func timeString(_ date: Date, calendar: Calendar = .current) -> String {
        let style = Date.FormatStyle(locale: russian, calendar: calendar, timeZone: calendar.timeZone)
            .hour(.twoDigits(amPM: .omitted))
            .minute(.twoDigits)
        return date.formatted(style)
    }
}

extension String {
    /// «Завтра, 09:00» → «завтра, 09:00».
    var lowercasedFirst: String {
        prefix(1).lowercased() + String(dropFirst())
    }
}
