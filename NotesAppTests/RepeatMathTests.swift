import XCTest
@testable import NotesApp

final class RepeatMathTests: XCTestCase {
    private let calendar = TestCalendar.moscow
    private func d(_ text: String) -> Date { TestCalendar.date(text) }

    /// Каждый месяц 31-го: в коротких месяцах — последний день, потом снова 31-е.
    func testMonthlyKeepsDayOfMonth() {
        let dates = RepeatMath.upcoming(start: d("2026-01-31 10:00"), rule: .monthly,
                                        after: d("2026-01-31 10:00"), until: d("2026-05-01 00:00"),
                                        limit: 10, calendar: calendar)
        XCTAssertEqual(dates, [d("2026-02-28 10:00"), d("2026-03-31 10:00"), d("2026-04-30 10:00")])
    }

    func testUpcomingSkipsPast() {
        let dates = RepeatMath.upcoming(start: d("2026-10-10 09:00"), rule: .daily,
                                        after: d("2026-10-16 22:24"), until: .distantFuture,
                                        limit: 2, calendar: calendar)
        XCTAssertEqual(dates, [d("2026-10-17 09:00"), d("2026-10-18 09:00")])
    }

    func testNonRepeatingOnlyWhenInFuture() {
        let now = d("2026-10-16 22:24")
        XCTAssertEqual(RepeatMath.upcoming(start: d("2026-10-16 20:00"), rule: nil, after: now,
                                           until: .distantFuture, limit: 5, calendar: calendar), [])
        XCTAssertEqual(RepeatMath.upcoming(start: d("2026-10-17 09:00"), rule: nil, after: now,
                                           until: .distantFuture, limit: 5, calendar: calendar),
                       [d("2026-10-17 09:00")])
    }

    /// «Готово» на просроченном еженедельном деле → ближайший четверг после сегодня.
    func testNextAfterOverdueWeekly() {
        let next = RepeatMath.next(after: d("2026-10-01 18:00"), rule: .weekly,
                                   now: d("2026-10-16 22:24"), calendar: calendar)
        XCTAssertEqual(next, d("2026-10-22 18:00"))
    }

    /// «Готово» заранее, до срока → следующий раз после срока.
    func testNextWhenDoneEarly() {
        let next = RepeatMath.next(after: d("2026-10-17 09:00"), rule: .daily,
                                   now: d("2026-10-16 22:24"), calendar: calendar)
        XCTAssertEqual(next, d("2026-10-18 09:00"))
    }
}
