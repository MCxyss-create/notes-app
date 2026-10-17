import XCTest
@testable import NotesApp

private struct FakeItem: FeedGroupable {
    let name: String
    var dueAt: Date?
    var isDone: Bool = false
    var doneAt: Date? = nil
    var createdAt: Date = Date(timeIntervalSince1970: 0)
}

final class FeedGroupingTests: XCTestCase {
    private let calendar = TestCalendar.moscow
    private func d(_ text: String) -> Date { TestCalendar.date(text) }

    /// Пятница, 22:24 — каждое дело попадает в свой блок.
    func testEachReminderLandsInItsSection() {
        let now = d("2026-10-16 22:24")
        let items = [
            FakeItem(name: "просрочено", dueAt: d("2026-10-16 20:00")),
            FakeItem(name: "сегодня", dueAt: d("2026-10-16 23:00")),
            FakeItem(name: "завтра", dueAt: d("2026-10-17 09:00")),
            FakeItem(name: "позже", dueAt: d("2026-10-18 00:00")),
            FakeItem(name: "без срока", dueAt: nil),
            FakeItem(name: "сделано", dueAt: d("2026-10-16 10:00"), isDone: true, doneAt: d("2026-10-16 11:00")),
        ]

        let groups = FeedGrouping.group(items, now: now, calendar: calendar)

        XCTAssertEqual(groups.map(\.section), [.overdue, .today, .tomorrow, .later, .noDate, .done])
        XCTAssertEqual(groups.map { $0.items.map(\.name) },
                       [["просрочено"], ["сегодня"], ["завтра"], ["позже"], ["без срока"], ["сделано"]])
    }

    /// Пустые блоки не показываются, внутри блока — по времени.
    func testEmptySectionsSkippedAndSortedByTime() {
        let now = d("2026-10-16 08:00")
        let items = [
            FakeItem(name: "вечер", dueAt: d("2026-10-16 19:00")),
            FakeItem(name: "утро", dueAt: d("2026-10-16 09:00")),
            FakeItem(name: "обед", dueAt: d("2026-10-16 13:00")),
        ]

        let groups = FeedGrouping.group(items, now: now, calendar: calendar)

        XCTAssertEqual(groups.map(\.section), [.today])
        XCTAssertEqual(groups.first?.items.map(\.name), ["утро", "обед", "вечер"])
    }

    /// Дело на сегодня, время которого прошло, — уже просрочено.
    func testPassedTodayIsOverdue() {
        let now = d("2026-10-16 12:01")
        let items = [FakeItem(name: "в полдень", dueAt: d("2026-10-16 12:00"))]

        let groups = FeedGrouping.group(items, now: now, calendar: calendar)

        XCTAssertEqual(groups.map(\.section), [.overdue])
    }
}
