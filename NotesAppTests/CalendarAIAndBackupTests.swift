import XCTest
@testable import NotesApp

/// Календарь в ответе ИИ, в промте и в резервной копии.
final class CalendarAIAndBackupTests: XCTestCase {
    private let now = TestCalendar.date("2026-10-16 22:24")
    private let defaults = ParseDefaults(hour: 9, minute: 0, beforeMin: 15)

    private func parse(_ json: String) throws -> AIResult {
        try AIParser.parse(json, reference: now, now: now, defaults: defaults, calendar: TestCalendar.moscow)
    }

    /// «у Лёши день рождения 12 марта» → событие без года, напоминания по умолчанию.
    func testBirthdayEvent() throws {
        let result = try parse(#"""
        {"items":[],"events":[{"type":"birthday","title":"Лёша","date":"--03-12","year":null}],"reply":"Добавил."}
        """#)
        XCTAssertTrue(result.drafts.isEmpty)
        XCTAssertFalse(result.answered)
        XCTAssertEqual(result.events.count, 1)
        let event = try XCTUnwrap(result.events.first)
        XCTAssertEqual(event.type, .birthday)
        XCTAssertEqual(event.title, "Лёша")
        XCTAssertEqual([event.month, event.day], [3, 12])
        XCTAssertNil(event.year)
        XCTAssertEqual(event.remindDays, [0, 1])
        XCTAssertTrue(AIControlCheck.problems(result, expected: AIControlCheck.eventCases[0]).isEmpty)
    }

    /// «годовщина родителей 5 июня 1999» → год из даты, свои напоминания.
    func testAnniversaryWithYear() throws {
        let result = try parse(#"""
        {"events":[{"type":"anniversary","title":"Годовщина свадьбы родителей","date":"1999-06-05","remind_days":[7,0,7]}],"reply":"ок"}
        """#)
        let event = try XCTUnwrap(result.events.first)
        XCTAssertEqual(event.type, .anniversary)
        XCTAssertEqual(event.year, 1999)
        XCTAssertEqual(event.remindDays, [0, 7])
        XCTAssertTrue(AIControlCheck.problems(result, expected: AIControlCheck.eventCases[1]).isEmpty)
        // А если вместо события создано дело — проверка это ловит.
        let wrong = try parse(#"{"items":[{"kind":"reminder","title":"Годовщина","due":"2027-06-05"}],"reply":"ок"}"#)
        XCTAssertFalse(AIControlCheck.problems(wrong, expected: AIControlCheck.eventCases[1]).isEmpty)
    }

    /// Неверная дата (31 февраля) и пустое имя — отбрасываем; другие форматы даты понимаем.
    func testBadEventsAreDropped() throws {
        let result = try parse(#"""
        {"events":[
          {"type":"birthday","title":"Вася","date":"--02-31"},
          {"type":"birthday","title":"  ","date":"--05-20"},
          {"type":"party","title":"Встреча выпускников.","date":"14.02"},
          {"type":"birthday","title":"Ваня","date":"2008-02-29"}
        ],"reply":"ок"}
        """#)
        XCTAssertEqual(result.events.map(\.title), ["Встреча выпускников", "Ваня"])
        XCTAssertEqual(result.events[0].type, .other)
        XCTAssertEqual([result.events[0].month, result.events[0].day], [2, 14])
        XCTAssertEqual(result.events[1].year, 2008)
        XCTAssertNil(AIParser.eventDate("2026-13-01"))
        XCTAssertEqual(AIParser.eventDate("12.03.1999")?.year, 1999)
    }

    func testPromptDescribesEvents() {
        let prompt = AIPrompt.system(now: now, calendar: TestCalendar.moscow, defaultHour: 9, defaultMinute: 0,
                                     defaultBefore: 15)
        XCTAssertTrue(prompt.contains("\"events\""))
        XCTAssertTrue(prompt.contains("\"--ММ-ДД\""))
        XCTAssertTrue(prompt.contains("не reminder"))
        XCTAssertEqual(AIControlCheck.eventCases.count, 2)
    }

    /// Siri: только событие — так и отвечаем.
    func testSiriTextForEvent() {
        let event = EventDraft(type: .birthday, title: "Лёша", month: 3, day: 12)
        XCTAssertEqual(QuickCaptureText.saved([], reply: "", events: [event]), "Добавил в календарь: Лёша, 12 марта.")
    }

    /// Копия с событиями туда-обратно; при восстановлении — без дублей по uid.
    func testBackupWithEvents() throws {
        let event = BackupEvent(uid: UUID(), title: "Лёша", type: "birthday", month: 3, day: 12, year: 2008,
                                note: "Подарок", remindDays: [0, 1], remindMinutes: 540, source: "contacts",
                                contactID: "c1", createdAt: TestCalendar.date("2026-10-18 10:00"))
        let file = try Backup.decode(Backup.encode([], events: [event, event],
                                                   exportedAt: TestCalendar.date("2026-10-19 12:00")))
        XCTAssertEqual(file.version, 4)
        XCTAssertEqual(file.events, [event, event])
        XCTAssertEqual(Backup.newEvents(in: file, existing: []), [event])
        XCTAssertEqual(Backup.newEvents(in: file, existing: [event.uid]), [])
    }

    /// Старая копия (версия 3, без календаря) читается как раньше.
    func testOldBackupWithoutEvents() throws {
        let json = """
        {"app":"Мысли","version":3,"exportedAt":"2026-10-18T09:00:00Z","items":[],"folders":[],"photos":[]}
        """
        let file = try Backup.decode(Data(json.utf8))
        XCTAssertNil(file.events)
        XCTAssertEqual(Backup.newEvents(in: file, existing: []), [])
    }
}
