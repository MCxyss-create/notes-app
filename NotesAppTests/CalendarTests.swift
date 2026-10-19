import XCTest
@testable import NotesApp

/// Календарь: ближайшая дата, 29 февраля, возраст, праздники, уведомления, контакты.
final class CalendarTests: XCTestCase {
    private let calendar = TestCalendar.moscow
    private func d(_ text: String) -> Date { TestCalendar.date(text) }

    private func birthday(_ title: String, _ month: Int, _ day: Int, year: Int? = nil,
                          remind: [Int] = [0, 1]) -> CalendarEntry {
        CalendarEntry(id: title, title: title, type: .birthday, month: month, day: day, year: year, remindDays: remind)
    }

    func testNextDateTodayAndYearRollover() {
        let now = d("2026-10-18 20:00")
        // Сегодня — сегодня, даже вечером.
        XCTAssertEqual(CalendarMath.next(birthday("Лёша", 10, 18), from: now, calendar: calendar), d("2026-10-18 00:00"))
        XCTAssertEqual(CalendarMath.next(birthday("Лёша", 10, 19), from: now, calendar: calendar), d("2026-10-19 00:00"))
        // Уже прошло — через год.
        XCTAssertEqual(CalendarMath.next(birthday("Лёша", 3, 12), from: now, calendar: calendar), d("2027-03-12 00:00"))
        XCTAssertEqual(CalendarMath.next(birthday("Новый", 1, 1), from: d("2026-12-31 23:00"), calendar: calendar),
                       d("2027-01-01 00:00"))
    }

    /// 29 февраля: в невисокосный год — 28-го, в високосный — 29-го.
    func testLeapDay() {
        let leap = birthday("Ваня", 2, 29)
        XCTAssertEqual(CalendarMath.next(leap, from: d("2026-10-18 12:00"), calendar: calendar), d("2027-02-28 00:00"))
        XCTAssertEqual(CalendarMath.next(leap, from: d("2027-03-01 12:00"), calendar: calendar), d("2028-02-29 00:00"))
        XCTAssertEqual(CalendarMath.entries(on: d("2027-02-28 10:00"), in: [leap], calendar: calendar), [leap])
        XCTAssertTrue(CalendarMath.entries(on: d("2028-02-28 10:00"), in: [leap], calendar: calendar).isEmpty)
        XCTAssertTrue(CalendarMath.isValid(month: 2, day: 29))
        XCTAssertFalse(CalendarMath.isValid(month: 2, day: 30))
        XCTAssertFalse(CalendarMath.isValid(month: 4, day: 31))
        XCTAssertFalse(CalendarMath.isValid(month: 13, day: 1))
    }

    func testAgeTexts() {
        let lesha = birthday("Лёша", 10, 19, year: 2008)
        let date = CalendarMath.next(lesha, from: d("2026-10-18 12:00"), calendar: calendar)!
        let years = CalendarMath.years(lesha, on: date, calendar: calendar)
        XCTAssertEqual(years, 18)
        XCTAssertEqual(CalendarMath.ageText(.birthday, years: years, isToday: false), "исполнится 18")
        XCTAssertEqual(CalendarMath.ageText(.birthday, years: years, isToday: true), "18 лет")
        XCTAssertEqual(CalendarMath.ageText(.anniversary, years: 1, isToday: false), "1 год")
        XCTAssertEqual(CalendarMath.ageText(.anniversary, years: 22, isToday: true), "22 года")
        XCTAssertNil(CalendarMath.ageText(.birthday, years: nil, isToday: true))
        XCTAssertEqual(CalendarMath.remindText([1, 0]), "напомню в день и за день")
        XCTAssertEqual(CalendarMath.remindText([7, 0, 3]), "напомню в день, за 3 дня и за неделю")
        XCTAssertEqual(CalendarMath.remindText([]), "без напоминания")
    }

    func testUpcomingAndWhenText() {
        let now = d("2026-10-31 12:00")
        let entries = [birthday("Лёша", 11, 1, year: 2008)] + RussianHolidays.entries()
        let soon = CalendarMath.upcoming(entries, from: now, days: 30, calendar: calendar)
        XCTAssertEqual(soon.map(\.entry.title), ["Лёша", "День народного единства"])
        XCTAssertEqual(soon.first?.years, 18)
        XCTAssertEqual(CalendarMath.whenText(soon[0].date, from: now, calendar: calendar), "Завтра")
        XCTAssertEqual(CalendarMath.whenText(soon[1].date, from: now, calendar: calendar), "через 4 дня")
    }

    /// Сетка октября 2026: 1-е — четверг, неделя с понедельника → три пустые клетки.
    func testMonthGridStartsOnMonday() {
        var monday = calendar
        monday.firstWeekday = 2
        let cells = CalendarMath.monthGrid(year: 2026, month: 10, calendar: monday)
        XCTAssertEqual(cells.prefix(3).filter { $0 == nil }.count, 3)
        XCTAssertEqual(cells.compactMap { $0 }.count, 31)
    }

    func testRussianHolidays() {
        let all = RussianHolidays.entries()
        XCTAssertEqual(all.filter { !$0.unofficial }.count, 8)
        XCTAssertEqual(all.filter(\.unofficial).map(\.title), ["День святого Валентина", "День знаний", "Канун Нового года"])
        XCTAssertTrue(all.contains { $0.month == 11 && $0.day == 4 && $0.title == "День народного единства" })
        let hidden = RussianHolidays.hidden(from: "02-14, 12-31,")
        XCTAssertEqual(hidden, ["02-14", "12-31"])
        XCTAssertEqual(RussianHolidays.entries(hidden: hidden).count, 9)
        XCTAssertEqual(RussianHolidays.text(from: hidden), "02-14,12-31")
        XCTAssertEqual(RussianHolidays.holidayID(fromEntryID: "holiday-11-04"), "11-04")
    }

    func testPlannerTextsAndDaysBefore() {
        let now = d("2026-10-18 12:00")
        let lesha = birthday("Лёша", 10, 19, year: 2008, remind: [0, 1, 7])
        let plan = CalendarPlanner.plan([lesha], now: now, defaultMinutes: 9 * 60, calendar: calendar)
        // «за неделю» уже прошло, «за день» — сегодня в 09:00 тоже прошло; остаётся в сам день.
        XCTAssertEqual(plan.map(\.date), [d("2026-10-19 09:00")])
        XCTAssertEqual(plan.first?.title, "🎂 Сегодня день рождения: Лёша — 18 лет")
        XCTAssertTrue(plan.first?.id.hasPrefix(CalendarPlanner.idPrefix) ?? false)

        let later = CalendarPlanner.plan([birthday("Аня", 11, 1, remind: [0, 1, 3])], now: now,
                                         defaultMinutes: 9 * 60, calendar: calendar)
        XCTAssertEqual(later.map(\.title), ["Через 3 дня день рождения: Аня", "Завтра день рождения: Аня",
                                            "🎂 Сегодня день рождения: Аня"])
        XCTAssertEqual(later.first?.body, "1 ноября")

        // Своё время напоминания.
        var custom = birthday("Оля", 10, 20, remind: [0])
        custom.remindMinutes = 8 * 60 + 30
        XCTAssertEqual(CalendarPlanner.plan([custom], now: now, defaultMinutes: 540, calendar: calendar).map(\.date),
                       [d("2026-10-20 08:30")])
    }

    /// Праздники напоминают, только если их передали (включено «Напоминать о праздниках»).
    func testHolidaysOnlyWhenRemindersOn() {
        let now = d("2026-10-31 12:00")
        XCTAssertTrue(CalendarPlanner.plan([], now: now, defaultMinutes: 540, calendar: calendar).isEmpty)
        let holidays = CalendarPlanner.plan(RussianHolidays.entries(), now: now, defaultMinutes: 540, calendar: calendar)
        XCTAssertEqual(holidays.first?.title, "🎉 Сегодня: День народного единства")
    }

    /// Больше 8 событий — только 8 ближайших; и общий лимит iOS 64 не превышен.
    func testCalendarLimitAndTotal() {
        let now = d("2026-10-18 12:00")
        let many = (1...20).map { birthday("Друг \($0)", 10 + ($0 > 12 ? 1 : 0), ($0 % 12) + 19, remind: [0]) }
        let plan = CalendarPlanner.plan(many, now: now, defaultMinutes: 540, calendar: calendar)
        XCTAssertEqual(plan.count, CalendarPlanner.limit)
        XCTAssertEqual(plan.map(\.date), plan.map(\.date).sorted())

        let summaries = SummaryPlanner.daysAhead * 2
        XCTAssertLessThanOrEqual(NotificationPlanner.defaultLimit + CalendarPlanner.limit + summaries + 2, 64)
        XCTAssertTrue(NotificationPlanner.managedPrefixes.contains(CalendarPlanner.idPrefix))
        XCTAssertEqual(NotificationLevel.for(id: "event-abc-0-2026-10-19"), .timeSensitive)
    }

    /// Утренняя сводка: если сегодня ДР или праздник — строка «Сегодня: …».
    func testMorningSummaryMentionsOccasions() {
        let now = d("2026-11-03 20:00")
        let task = ReminderInput(id: UUID(), title: "Сдать пробник", details: nil, dueAt: d("2026-11-04 13:30"),
                                 remindBeforeMin: nil, isDone: false)
        let events = [birthday("Лёша", 11, 4)] + RussianHolidays.entries()
        let plan = SummaryPlanner.plan([task], now: now, settings: SummarySettings.standard, events: events,
                                       calendar: calendar)
        let morning = plan.first { $0.id.contains("morning") }
        XCTAssertEqual(morning?.body.components(separatedBy: "\n").last, "Сегодня: 🎂 Лёша, День народного единства")
    }

    func testContactToBirthday() {
        var parts = DateComponents()
        parts.month = 3
        parts.day = 12
        XCTAssertEqual(ContactBirthday.make(contactID: "c1", givenName: " Алексей ", familyName: "Петров", birthday: parts),
                       ContactBirthday(contactID: "c1", title: "Алексей Петров", month: 3, day: 12, year: nil))
        parts.year = 2008
        XCTAssertEqual(ContactBirthday.make(contactID: "c1", givenName: "", familyName: "", nickname: "Лёша",
                                            birthday: parts)?.year, 2008)
        // «Без года» в Контактах — это 1604.
        parts.year = 1604
        XCTAssertNil(ContactBirthday.make(contactID: "c1", givenName: "Лёша", familyName: "", birthday: parts)?.year)
        XCTAssertNil(ContactBirthday.make(contactID: "c2", givenName: "Лёша", familyName: "", birthday: nil))
        XCTAssertNil(ContactBirthday.make(contactID: "c3", givenName: "", familyName: "", birthday: parts))
        var wrong = DateComponents()
        wrong.month = 2
        wrong.day = 31
        XCTAssertNil(ContactBirthday.make(contactID: "c4", givenName: "Ира", familyName: "", birthday: wrong))
    }

    /// Повторный импорт обновляет по контакту, своё событие с тем же именем и датой не двоит.
    func testContactImportDecisions() {
        let known = UUID()
        let manual = UUID()
        let existing = [
            ContactBirthday.Known(uid: known, contactID: "c1", title: "Лёша", month: 3, day: 12),
            ContactBirthday.Known(uid: manual, contactID: nil, title: "Мама", month: 5, day: 20),
        ]
        let again = ContactBirthday(contactID: "c1", title: "Алексей", month: 3, day: 13, year: nil)
        XCTAssertEqual(again.action(existing: existing), .update(known))
        let mom = ContactBirthday(contactID: "c2", title: "мама", month: 5, day: 20, year: 1975)
        XCTAssertEqual(mom.action(existing: existing), .skip)
        let fresh = ContactBirthday(contactID: "c3", title: "Ира", month: 1, day: 2, year: nil)
        XCTAssertEqual(fresh.action(existing: existing), .add)
    }
}
