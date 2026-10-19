import Foundation

/// Праздники РФ. Считаются в коде, в базу и в копию не пишутся.
enum RussianHolidays {
    struct Holiday: Identifiable, Equatable {
        let month: Int
        let day: Int
        let title: String
        /// Неофициальные — 14 февраля, 1 сентября, 31 декабря.
        let official: Bool

        /// «11-04» — по нему праздник можно скрыть.
        var id: String { String(format: "%02d-%02d", month, day) }
    }

    static let all: [Holiday] = [
        Holiday(month: 1, day: 1, title: "Новый год", official: true),
        Holiday(month: 1, day: 7, title: "Рождество Христово", official: true),
        Holiday(month: 2, day: 14, title: "День святого Валентина", official: false),
        Holiday(month: 2, day: 23, title: "День защитника Отечества", official: true),
        Holiday(month: 3, day: 8, title: "Международный женский день", official: true),
        Holiday(month: 5, day: 1, title: "Праздник Весны и Труда", official: true),
        Holiday(month: 5, day: 9, title: "День Победы", official: true),
        Holiday(month: 6, day: 12, title: "День России", official: true),
        Holiday(month: 9, day: 1, title: "День знаний", official: false),
        Holiday(month: 11, day: 4, title: "День народного единства", official: true),
        Holiday(month: 12, day: 31, title: "Канун Нового года", official: false),
    ]

    /// Праздники для календаря, кроме скрытых. Напоминание — в сам день.
    static func entries(hidden: Set<String> = []) -> [CalendarEntry] {
        all.filter { !hidden.contains($0.id) }.map {
            CalendarEntry(id: "holiday-\($0.id)", title: $0.title, type: .holiday, month: $0.month, day: $0.day,
                          remindDays: [0], unofficial: !$0.official)
        }
    }

    /// id праздника из id события календаря («holiday-11-04» → «11-04»), не праздник — nil.
    static func holidayID(fromEntryID id: String) -> String? {
        id.hasPrefix("holiday-") ? String(id.dropFirst("holiday-".count)) : nil
    }

    /// Скрытые праздники хранятся строкой «02-14,12-31».
    static func hidden(from text: String) -> Set<String> {
        Set(text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    static func text(from hidden: Set<String>) -> String {
        hidden.sorted().joined(separator: ",")
    }
}
