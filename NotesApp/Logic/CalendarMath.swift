import Foundation

/// Событие календаря без SwiftData — для расчётов, уведомлений и тестов.
/// Свои события (`CalendarEvent.entry`) и праздники РФ (`RussianHolidays`) выглядят одинаково.
struct CalendarEntry: Identifiable, Equatable {
    let id: String
    var title: String
    var type: EventType
    var month: Int
    var day: Int
    var year: Int? = nil
    var remindDays: [Int] = [0, 1]
    var remindMinutes: Int? = nil
    /// Праздник «неофициальный»: 14 февраля, 1 сентября, 31 декабря.
    var unofficial = false
}

/// Событие до сохранения: в форме или на карточке «Вот что я понял».
struct EventDraft: Identifiable, Equatable {
    let id = UUID()
    var type: EventType
    var title: String
    var month: Int
    var day: Int
    var year: Int? = nil
    var note: String? = nil
    var remindDays: [Int] = [0, 1]
    var remindMinutes: Int? = nil
    /// Сохранять ли эту карточку.
    var include = true

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && CalendarMath.isValid(month: month, day: day)
    }
}

/// Событие в конкретный день: ближайший раз.
struct Occurrence: Identifiable, Equatable {
    let entry: CalendarEntry
    /// Начало дня.
    let date: Date
    /// Сколько исполнится / сколько лет — если известен год.
    let years: Int?

    var id: String { "\(entry.id)@\(Int(date.timeIntervalSince1970))" }
}

/// Даты, которые повторяются каждый год. 29 февраля в невисокосный год — 28 февраля.
enum CalendarMath {
    /// Варианты «Напомнить»: в день, за день, за 3 дня, за неделю.
    static let remindOptions = [0, 1, 3, 7]

    static let monthsGenitive = ["января", "февраля", "марта", "апреля", "мая", "июня",
                                 "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    static let monthsNominative = ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь",
                                   "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"]

    static func isLeap(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    static func daysIn(month: Int, leap: Bool) -> Int {
        guard (1...12).contains(month) else { return 0 }
        return [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
    }

    /// Бывает ли такой день. 29 февраля — бывает (в високосные годы), 31 февраля — нет.
    static func isValid(month: Int, day: Int) -> Bool {
        day >= 1 && day <= daysIn(month: month, leap: true)
    }

    /// Дата события в году (начало дня). 29 февраля в невисокосный год → 28 февраля.
    static func date(month: Int, day: Int, in year: Int, calendar: Calendar) -> Date? {
        guard isValid(month: month, day: day) else { return nil }
        let fixedDay = (month == 2 && day == 29 && !isLeap(year)) ? 28 : day
        return calendar.date(from: DateComponents(year: year, month: month, day: fixedDay))
    }

    /// Ближайший раз: сегодня или позже.
    static func next(_ entry: CalendarEntry, from now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        let year = calendar.component(.year, from: today)
        for candidate in year...(year + 1) {
            if let date = date(month: entry.month, day: entry.day, in: candidate, calendar: calendar), date >= today {
                return date
            }
        }
        return nil
    }

    /// Сколько лет в этот день, если известен год. В сам год события — ничего.
    static func years(_ entry: CalendarEntry, on date: Date, calendar: Calendar) -> Int? {
        guard let start = entry.year else { return nil }
        let years = calendar.component(.year, from: date) - start
        return years > 0 ? years : nil
    }

    /// События этого дня. 28 февраля невисокосного года — и те, что 29-го.
    static func entries(on date: Date, in entries: [CalendarEntry], calendar: Calendar) -> [CalendarEntry] {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return [] }
        return entries.filter { entry in
            if entry.month == month && entry.day == day { return true }
            return month == 2 && day == 28 && entry.month == 2 && entry.day == 29 && !isLeap(year)
        }
        .sorted(by: order)
    }

    /// Ближайшие days дней, сегодня включительно, по дате.
    static func upcoming(_ entries: [CalendarEntry], from now: Date, days: Int, calendar: Calendar) -> [Occurrence] {
        let today = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: days, to: today) else { return [] }
        return entries
            .compactMap { entry -> Occurrence? in
                guard let date = next(entry, from: now, calendar: calendar), date < end else { return nil }
                return Occurrence(entry: entry, date: date, years: years(entry, on: date, calendar: calendar))
            }
            .sorted { a, b in
                a.date != b.date ? a.date < b.date : order(a.entry, b.entry)
            }
    }

    /// Сначала ДР, потом годовщины, свои даты и праздники; внутри — по имени.
    static func order(_ a: CalendarEntry, _ b: CalendarEntry) -> Bool {
        let rank: [EventType: Int] = [.birthday: 0, .anniversary: 1, .other: 2, .holiday: 3]
        if a.type != b.type { return rank[a.type, default: 9] < rank[b.type, default: 9] }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }

    /// Клетки месяца для сетки: сначала пустые до первого числа (неделя — как в календаре).
    static func monthGrid(year: Int, month: Int, calendar: Calendar) -> [Date?] {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for day in range {
            cells.append(calendar.date(byAdding: .day, value: day - 1, to: first))
        }
        return cells
    }

    /// Сколько дней от сегодня до даты.
    static func days(from now: Date, to date: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// «Сегодня», «Завтра», «Послезавтра», «через 5 дней».
    static func whenText(_ date: Date, from now: Date, calendar: Calendar) -> String {
        let n = days(from: now, to: date, calendar: calendar)
        switch n {
        case ...0: return "Сегодня"
        case 1: return "Завтра"
        case 2: return "Послезавтра"
        default: return "через \(n) \(RussianPlural.pick(n, "день", "дня", "дней"))"
        }
    }

    /// «1 год», «22 года», «18 лет».
    static func yearsText(_ n: Int) -> String {
        "\(n) \(RussianPlural.pick(n, "год", "года", "лет"))"
    }

    /// ДР впереди — «исполнится 18», сегодня — «18 лет»; годовщина — «5 лет».
    static func ageText(_ type: EventType, years: Int?, isToday: Bool) -> String? {
        guard let years, years > 0 else { return nil }
        if type == .birthday && !isToday {
            return "исполнится \(years)"
        }
        return yearsText(years)
    }

    /// «12 марта».
    static func dayMonthText(month: Int, day: Int) -> String {
        guard (1...12).contains(month) else { return "\(day)" }
        return "\(day) \(monthsGenitive[month - 1])"
    }

    /// «🎂 Лёша» для ДР, иначе название — для «Ближайших» и сводки.
    static func label(_ entry: CalendarEntry) -> String {
        entry.type == .birthday ? "🎂 \(entry.title)" : entry.title
    }

    /// «напомню в день и за день», «без напоминания».
    static func remindText(_ days: [Int]) -> String {
        let words = Array(Set(days)).sorted().map { n -> String in
            switch n {
            case 0: return "в день"
            case 1: return "за день"
            case 7: return "за неделю"
            default: return "за \(n) \(RussianPlural.pick(n, "день", "дня", "дней"))"
            }
        }
        guard let last = words.last else { return "без напоминания" }
        if words.count == 1 { return "напомню \(last)" }
        return "напомню " + words.dropLast().joined(separator: ", ") + " и " + last
    }
}
