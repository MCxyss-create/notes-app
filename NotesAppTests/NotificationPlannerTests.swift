import XCTest
@testable import NotesApp

final class NotificationPlannerTests: XCTestCase {
    private let now = TestCalendar.date("2026-10-16 22:24")

    private func reminder(_ title: String, _ due: String?, before: Int? = 15, done: Bool = false) -> ReminderInput {
        ReminderInput(id: UUID(), title: title, details: nil,
                      dueAt: due.map { TestCalendar.date($0) },
                      remindBeforeMin: before, isDone: done)
    }

    /// «Завтра подойти к учителю» в 09:00 → уведомление в 08:45 и в 09:00.
    func testDueAndEarlyNotifications() {
        let plan = NotificationPlanner.plan([reminder("Подойти к учителю", "2026-10-17 09:00")], now: now)

        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan[0].date, TestCalendar.date("2026-10-17 08:45"))
        XCTAssertEqual(plan[0].body, "Через 15 минут")
        XCTAssertEqual(plan[1].date, TestCalendar.date("2026-10-17 09:00"))
        XCTAssertEqual(plan[1].title, "Подойти к учителю")
        XCTAssertEqual(plan[1].body, "Пора!")
    }

    func testSkipsDonePastAndUndated() {
        let plan = NotificationPlanner.plan([
            reminder("сделано", "2026-10-17 09:00", done: true),
            reminder("прошло", "2026-10-16 20:00"),
            reminder("без срока", nil),
        ], now: now)

        XCTAssertTrue(plan.isEmpty)
    }

    /// Дело через 6 минут с «за 15 минут»: раннее уже прошло, остаётся только точное.
    func testEarlySkippedWhenAlreadyPassed() {
        let plan = NotificationPlanner.plan([reminder("скоро", "2026-10-16 22:30")], now: now)

        XCTAssertEqual(plan.map(\.date), [TestCalendar.date("2026-10-16 22:30")])
    }

    /// 100 дел → ставим только ближайшие (56: остальные места — сводкам и переподписи), по порядку.
    func testLimitKeepsNearest() {
        let many = (1...100).map { i in
            ReminderInput(id: UUID(), title: "Дело \(i)", details: nil,
                          dueAt: now.addingTimeInterval(Double(i) * 3600),
                          remindBeforeMin: nil, isDone: false)
        }

        let plan = NotificationPlanner.plan(many, now: now)
        let limit = NotificationPlanner.defaultLimit

        XCTAssertEqual(limit, 56)
        XCTAssertEqual(plan.count, limit)
        XCTAssertEqual(plan.first?.title, "Дело 1")
        XCTAssertEqual(plan.last?.title, "Дело \(limit)")
        XCTAssertTrue(zip(plan, plan.dropFirst()).allSatisfy { $0.date <= $1.date })
    }

    /// Уведомление знает свою запись — для кнопок «Готово / Через час / Завтра».
    func testNotificationsCarryItemID() {
        let r = reminder("кнопки", "2026-10-17 09:00")
        let plan = NotificationPlanner.plan([r], now: now)

        XCTAssertEqual(plan.map(\.itemID), [r.id, r.id])
        XCTAssertFalse(plan.contains { $0.repeating })
    }

    /// «Каждый день в 9»: срок уже прошёл, но следующие дни ставятся — до 8 раз вперёд, без повторов id.
    func testDailyRepeatSchedulesNextDays() {
        let r = ReminderInput(id: UUID(), title: "Витамины", details: nil,
                              dueAt: TestCalendar.date("2026-10-10 09:00"),
                              remindBeforeMin: nil, isDone: false, repeatRule: .daily)

        let plan = NotificationPlanner.plan([r], now: now, calendar: TestCalendar.moscow)

        XCTAssertEqual(plan.count, NotificationPlanner.perItemLimit)
        XCTAssertEqual(plan.first?.date, TestCalendar.date("2026-10-17 09:00"))
        XCTAssertEqual(plan.last?.date, TestCalendar.date("2026-10-24 09:00"))
        XCTAssertEqual(Set(plan.map(\.id)).count, plan.count)
        XCTAssertTrue(plan.allSatisfy { $0.repeating })
    }

    /// Дело через 2 месяца без повтора всё равно ставится (ограничение в 35 дней — только для повторов).
    func testFarReminderIsScheduled() {
        let plan = NotificationPlanner.plan([reminder("далеко", "2026-12-20 10:00", before: nil)], now: now)
        XCTAssertEqual(plan.map(\.date), [TestCalendar.date("2026-12-20 10:00")])
    }

    func testIdsAreStable() {
        let r = reminder("одно и то же", "2026-10-17 09:00")
        XCTAssertEqual(NotificationPlanner.plan([r], now: now).map(\.id),
                       NotificationPlanner.plan([r], now: now).map(\.id))
    }

    func testBeforeText() {
        XCTAssertEqual(NotificationPlanner.beforeText(5), "Через 5 минут")
        XCTAssertEqual(NotificationPlanner.beforeText(21), "Через 21 минуту")
        XCTAssertEqual(NotificationPlanner.beforeText(22), "Через 22 минуты")
        XCTAssertEqual(NotificationPlanner.beforeText(60), "Через час")
        XCTAssertEqual(NotificationPlanner.beforeText(120), "Через 2 часа")
        XCTAssertEqual(NotificationPlanner.beforeText(300), "Через 5 часов")
    }
}
