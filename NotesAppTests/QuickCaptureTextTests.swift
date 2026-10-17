import XCTest
@testable import NotesApp

final class QuickCaptureTextTests: XCTestCase {
    private let calendar = TestCalendar.moscow
    private func d(_ text: String) -> Date { TestCalendar.date(text) }

    private func draft(_ kind: ItemKind, _ title: String, due: Date? = nil) -> AIDraft {
        AIDraft(kind: kind, title: title, body: nil, due: due, timeGiven: true,
                remindBeforeMin: nil, repeatRule: nil, tags: [])
    }

    func testReplyFromAIWins() {
        let text = QuickCaptureText.saved([draft(.idea, "Бот")], reply: "Одна идея.", calendar: calendar)
        XCTAssertEqual(text, "Записал. Одна идея.")
    }

    func testSingleReminderWithoutReply() {
        let text = QuickCaptureText.saved([draft(.reminder, "Подойти к учителю", due: d("2026-10-17 09:00"))],
                                          reply: "", now: d("2026-10-16 22:24"), calendar: calendar)
        XCTAssertEqual(text, "Записал напоминание: Подойти к учителю, завтра, 09:00.")
    }

    func testSeveralAndNotes() {
        XCTAssertEqual(QuickCaptureText.saved([draft(.note, "А"), draft(.idea, "Б")], reply: " ", calendar: calendar),
                       "Записал 2 записи.")
        XCTAssertEqual(QuickCaptureText.saved([draft(.note, "Размер ноги")], reply: "", calendar: calendar),
                       "Записал заметку: Размер ноги.")
    }

    func testTodayText() {
        let entries = [
            SummaryPlanner.Entry(date: d("2026-10-17 09:00"), title: "Подойти к учителю"),
            SummaryPlanner.Entry(date: d("2026-10-17 13:30"), title: "Сдать пробник"),
        ]
        XCTAssertEqual(QuickCaptureText.today(entries, overdue: 1, calendar: calendar),
                       "Сегодня 2 дела: 09:00 Подойти к учителю, 13:30 Сдать пробник. Просрочено: 1.")
        XCTAssertEqual(QuickCaptureText.today([], overdue: 0, calendar: calendar), "На сегодня дел нет.")
    }
}
