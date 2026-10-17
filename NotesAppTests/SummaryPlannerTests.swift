import XCTest
@testable import NotesApp

final class SummaryPlannerTests: XCTestCase {
    private let calendar = TestCalendar.moscow
    private func d(_ text: String) -> Date { TestCalendar.date(text) }

    private func reminder(_ title: String, _ due: String, done: Bool = false, repeatRule: RepeatRule? = nil) -> ReminderInput {
        ReminderInput(id: UUID(), title: title, details: nil, dueAt: d(due),
                      remindBeforeMin: nil, isDone: done, repeatRule: repeatRule)
    }

    /// Пятница, 22:24: сегодняшние сводки прошли; дальше утро и вечер субботы и воскресенья.
    func testMorningAndEveningForNextDays() {
        let reminders = [
            reminder("Подойти к учителю", "2026-10-17 09:00"),
            reminder("Сдать пробник", "2026-10-17 13:30"),
            reminder("Уже сделано", "2026-10-17 10:00", done: true),
            reminder("Поздно сегодня", "2026-10-16 23:00"),
            reminder("Витамины", "2026-10-10 08:30", repeatRule: .daily),
        ]

        let plan = SummaryPlanner.plan(reminders, now: d("2026-10-16 22:24"), settings: .standard, calendar: calendar)

        XCTAssertEqual(plan.map(\.date), [
            d("2026-10-17 08:00"), d("2026-10-17 21:00"),
            d("2026-10-18 08:00"), d("2026-10-18 21:00"),
        ])
        XCTAssertEqual(plan[0].id, "summary-morning-2026-10-17")
        XCTAssertEqual(plan[0].title, "Сегодня 3 дела")
        XCTAssertEqual(plan[0].body, "08:30 Витамины · 09:00 Подойти к учителю · 13:30 Сдать пробник")
        XCTAssertEqual(plan[1].id, "summary-evening-2026-10-17")
        XCTAssertEqual(plan[1].title, "Завтра 1 дело")
        XCTAssertEqual(plan[1].body, "08:30 Витамины")
        XCTAssertNil(plan[0].itemID)
    }

    /// Утром сегодня — ещё и сколько просрочено.
    func testMorningCountsOverdue() {
        let reminders = [
            reminder("Вчерашнее", "2026-10-15 10:00"),
            reminder("Обед", "2026-10-16 12:00"),
        ]
        let settings = SummarySettings(morningOn: true, morningMinutes: 480, eveningOn: false, eveningMinutes: 1260)

        let plan = SummaryPlanner.plan(reminders, now: d("2026-10-16 07:00"), settings: settings, calendar: calendar)

        XCTAssertEqual(plan.first?.date, d("2026-10-16 08:00"))
        XCTAssertEqual(plan.first?.title, "Сегодня 1 дело")
        XCTAssertEqual(plan.first?.body, "12:00 Обед · просрочено: 1")
    }

    func testNothingWithoutTasksOrWhenOff() {
        let now = d("2026-10-16 07:00")
        XCTAssertTrue(SummaryPlanner.plan([], now: now, settings: .standard, calendar: calendar).isEmpty)

        let off = SummarySettings(morningOn: false, morningMinutes: 480, eveningOn: false, eveningMinutes: 1260)
        let plan = SummaryPlanner.plan([reminder("Дело", "2026-10-16 12:00")], now: now, settings: off, calendar: calendar)
        XCTAssertTrue(plan.isEmpty)
    }

    func testLongListIsShortened() {
        let reminders = (0..<7).map { reminder("Дело \($0)", "2026-10-17 1\($0):00") }
        let plan = SummaryPlanner.plan(reminders, now: d("2026-10-16 22:24"), settings: .standard, calendar: calendar)

        XCTAssertEqual(plan.first?.title, "Сегодня 7 дел")
        XCTAssertTrue(plan.first?.body.hasSuffix("· и ещё 2") ?? false)
    }
}
