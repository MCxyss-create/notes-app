import XCTest
import UserNotifications
@testable import NotesApp

final class NotificationLevelTests: XCTestCase {
    private func d(_ text: String) -> Date { TestCalendar.date(text) }

    func testItemsResignAndTestAreTimeSensitive() {
        let uid = "A1B2C3D4-0000-4000-8000-000000000001"
        XCTAssertEqual(NotificationLevel.for(id: "item-\(uid)-due-1760680800"), .timeSensitive)
        XCTAssertEqual(NotificationLevel.for(id: "item-\(uid)-before-1760679900"), .timeSensitive)
        XCTAssertEqual(NotificationLevel.for(id: "resign-reminder"), .timeSensitive)
        XCTAssertEqual(NotificationLevel.for(id: "test-\(UUID().uuidString)"), .timeSensitive)
    }

    func testSummariesStayActive() {
        XCTAssertEqual(NotificationLevel.for(id: "summary-morning-2026-10-18"), .active)
        XCTAssertEqual(NotificationLevel.for(id: "summary-evening-2026-10-18"), .active)
        XCTAssertEqual(NotificationLevel.for(id: "что-то-другое"), .active)
    }

    /// Те же id, что ставят планировщики: дела и переподпись — срочные, сводки — обычные.
    func testPlannersIDs() {
        let now = d("2026-10-17 12:00")
        let calendar = TestCalendar.moscow
        let reminder = ReminderInput(id: UUID(), title: "Позвонить маме", details: nil,
                                     dueAt: d("2026-10-18 18:00"), remindBeforeMin: 15, isDone: false)
        let items = NotificationPlanner.plan([reminder], now: now, calendar: calendar)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { NotificationLevel.for(id: $0.id) == .timeSensitive })

        let summaries = SummaryPlanner.plan([reminder], now: now, settings: SummarySettings.standard, calendar: calendar)
        XCTAssertFalse(summaries.isEmpty)
        XCTAssertTrue(summaries.allSatisfy { NotificationLevel.for(id: $0.id) == .active })

        let resign = ResignPlanner.plan(expiration: d("2026-10-24 12:30"), now: now)
        XCTAssertEqual(resign.map { NotificationLevel.for(id: $0.id) }, .timeSensitive)
    }
}
