import Foundation

/// Общие помощники для тестов: календарь Москвы и разбор дат вида "2026-10-16 22:24".
enum TestCalendar {
    static let moscow: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        calendar.locale = Locale(identifier: "ru_RU")
        return calendar
    }()

    static func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = moscow
        formatter.timeZone = moscow.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let date = formatter.date(from: text) else {
            fatalError("Неверная дата в тесте: \(text)")
        }
        return date
    }
}
