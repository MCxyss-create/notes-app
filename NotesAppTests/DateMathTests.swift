import XCTest
@testable import NotesApp

final class DateMathTests: XCTestCase {
    private let calendar = TestCalendar.moscow
    private func d(_ text: String) -> Date { TestCalendar.date(text) }

    func testTomorrowMorning() {
        let result = DateMath.tomorrow(hour: 9, minute: 0, from: d("2026-10-16 22:24"), calendar: calendar)
        XCTAssertEqual(result, d("2026-10-17 09:00"))
    }

    func testEveningIsTodayBefore19() {
        let result = DateMath.evening(from: d("2026-10-16 15:00"), calendar: calendar)
        XCTAssertEqual(result, d("2026-10-16 19:00"))
    }

    func testEveningIsTomorrowAfter19() {
        let result = DateMath.evening(from: d("2026-10-16 22:24"), calendar: calendar)
        XCTAssertEqual(result, d("2026-10-17 19:00"))
    }

    func testInOneHourDropsSecondsAndCrossesMidnight() {
        let now = d("2026-10-16 23:30").addingTimeInterval(45)
        let result = DateMath.inOneHour(from: now, calendar: calendar)
        XCTAssertEqual(result, d("2026-10-17 00:30"))
    }

    func testSnoozeHour() {
        let result = DateMath.snooze(.hour, due: d("2026-10-16 20:00"), timeGiven: true,
                                     defaultHour: 9, defaultMinute: 0,
                                     now: d("2026-10-16 22:24"), calendar: calendar)
        XCTAssertEqual(result, d("2026-10-16 23:24"))
    }

    /// «Завтра» для просроченного дела с точным временем: завтра в то же время.
    func testSnoozeTomorrowKeepsGivenTime() {
        let result = DateMath.snooze(.tomorrow, due: d("2026-10-15 15:00"), timeGiven: true,
                                     defaultHour: 9, defaultMinute: 0,
                                     now: d("2026-10-16 22:24"), calendar: calendar)
        XCTAssertEqual(result, d("2026-10-17 15:00"))
    }

    /// «Завтра» для дела без точного времени: завтра во время по умолчанию.
    func testSnoozeTomorrowUsesDefaultTime() {
        let result = DateMath.snooze(.tomorrow, due: d("2026-10-16 09:00"), timeGiven: false,
                                     defaultHour: 8, defaultMinute: 30,
                                     now: d("2026-10-16 22:24"), calendar: calendar)
        XCTAssertEqual(result, d("2026-10-17 08:30"))
    }
}
