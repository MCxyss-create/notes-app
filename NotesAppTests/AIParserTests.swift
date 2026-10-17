import XCTest
@testable import NotesApp

/// Ответ ИИ не принимаем на веру: проверяем JSON, заголовки, виды записей и даты.
final class AIParserTests: XCTestCase {
    private let now = TestCalendar.date("2026-10-16 22:24")
    private let defaults = ParseDefaults(hour: 9, minute: 0, beforeMin: 15)

    private func parse(_ json: String) throws -> AIResult {
        try AIParser.parse(json, reference: now, now: now, defaults: defaults, calendar: TestCalendar.moscow)
    }

    private func reminder(due: String?, rule: String? = nil, before: String = "null") -> String {
        let dueJSON = due.map { "\"\($0)\"" } ?? "null"
        let ruleJSON = rule.map { "\"\($0)\"" } ?? "null"
        return """
        {"items":[{"kind":"reminder","title":"Дело","due":\(dueJSON),"remind_before_min":\(before),"repeat":\(ruleJSON),"tags":[]}],"reply":"ок"}
        """
    }

    /// Пример ответа из CLAUDE.md.
    func testSampleFromPlan() throws {
        let result = try parse("""
        {"items":[{"kind":"reminder","title":"Подойти к учителю","body":null,
          "due":"2026-10-17T09:00:00+03:00","time_given":false,
          "remind_before_min":15,"repeat":null,"tags":["школа"]}],
         "reply":"Напоминание на завтра 09:00."}
        """)

        XCTAssertEqual(result.reply, "Напоминание на завтра 09:00.")
        XCTAssertEqual(result.drafts.count, 1)
        let draft = result.drafts[0]
        XCTAssertEqual(draft.kind, .reminder)
        XCTAssertEqual(draft.title, "Подойти к учителю")
        XCTAssertNil(draft.body)
        XCTAssertEqual(draft.due, TestCalendar.date("2026-10-17 09:00"))
        XCTAssertFalse(draft.timeGiven)
        XCTAssertEqual(draft.remindBeforeMin, 15)
        XCTAssertNil(draft.repeatRule)
        XCTAssertEqual(draft.tags, ["школа"])
        XCTAssertNil(draft.warning)
    }

    /// JSON в ```json … ```, дата без пояса — пояс телефона, «заранее» не сказано — по умолчанию.
    func testCodeFenceAndDateWithoutZone() throws {
        let json = "```json\n{\"items\":[{\"kind\":\"reminder\",\"title\":\"Позвонить маме.\",\"due\":\"2026-10-17T00:24:00\"}],\"reply\":\"ок\"}\n```"
        let draft = try parse(json).drafts[0]

        XCTAssertEqual(draft.title, "Позвонить маме")
        XCTAssertEqual(draft.due, TestCalendar.date("2026-10-17 00:24"))
        XCTAssertTrue(draft.timeGiven)
        XCTAssertEqual(draft.remindBeforeMin, 15)
    }

    func testNotJSONThrows() {
        XCTAssertThrowsError(try parse("Извини, не понял"))
        XCTAssertThrowsError(try parse("{\"text\":\"привет\"}"))
    }

    /// Пустой заголовок: берём из подробностей, а если и их нет — запись выбрасываем.
    func testEmptyTitle() throws {
        let result = try parse("""
        {"items":[{"kind":"note","title":"  ","body":"Пароль от Wi-Fi на даче"},{"kind":"idea","title":"","body":null}],"reply":""}
        """)

        XCTAssertEqual(result.drafts.map(\.title), ["Пароль от Wi-Fi на даче"])
        XCTAssertNil(result.drafts[0].body)
    }

    /// Неизвестный вид со сроком — напоминание; у идеи срок, повтор и «заранее» убираются.
    func testKinds() throws {
        let result = try parse("""
        {"items":[{"kind":"task","title":"Забрать посылку","due":"2026-10-17T15:00:00+03:00"},
                  {"kind":"Idea","title":"Бот для отчётов","due":"2026-10-17T15:00:00+03:00","repeat":"daily","remind_before_min":30},
                  {"title":"Размер ноги 43"}]}
        """)

        XCTAssertEqual(result.drafts.map(\.kind), [.reminder, .idea, .note])
        XCTAssertNil(result.drafts[1].due)
        XCTAssertNil(result.drafts[1].repeatRule)
        XCTAssertNil(result.drafts[1].remindBeforeMin)
    }

    /// «в 7 вечера» в 22:24: модель поставила сегодня 19:00 — переносим на завтра и предупреждаем.
    func testPassedTimeMovesToNextDay() throws {
        let draft = try parse(reminder(due: "2026-10-16T19:00:00+03:00")).drafts[0]

        XCTAssertEqual(draft.due, TestCalendar.date("2026-10-17 19:00"))
        XCTAssertNotNil(draft.warning)
    }

    /// Дата давно в прошлом (не тот год) — не угадываем, а просим проверить.
    func testOldDateKeptWithWarning() throws {
        let draft = try parse(reminder(due: "2025-10-17T09:00:00+03:00")).drafts[0]

        XCTAssertEqual(draft.due, TestCalendar.date("2025-10-17 09:00"))
        XCTAssertEqual(draft.warning, "Дата в прошлом — проверь")
    }

    /// Каждый вторник, а модель дала прошлый вторник — берём ближайший будущий.
    func testPastRepeatMovesToNextTime() throws {
        let draft = try parse(reminder(due: "2026-10-13T18:00:00+03:00", rule: "weekly")).drafts[0]

        XCTAssertEqual(draft.due, TestCalendar.date("2026-10-20 18:00"))
        XCTAssertEqual(draft.repeatRule, .weekly)
        XCTAssertNil(draft.warning)
    }

    /// Только день — время по умолчанию, time_given=false.
    func testDayOnlyGetsDefaultTime() throws {
        let draft = try parse(reminder(due: "2026-10-19")).drafts[0]

        XCTAssertEqual(draft.due, TestCalendar.date("2026-10-19 09:00"))
        XCTAssertFalse(draft.timeGiven)
    }

    func testRemindBefore() throws {
        XCTAssertEqual(try parse(reminder(due: "2026-10-19T08:30:00+03:00", before: "60")).drafts[0].remindBeforeMin, 60)
        XCTAssertEqual(try parse(reminder(due: "2026-10-19T08:30:00+03:00", before: "\"30\"")).drafts[0].remindBeforeMin, 30)
        XCTAssertNil(try parse(reminder(due: "2026-10-19T08:30:00+03:00", before: "0")).drafts[0].remindBeforeMin)
        XCTAssertNil(try parse(reminder(due: nil, before: "60")).drafts[0].remindBeforeMin)
    }

    /// Фраза ждала во «Входящих» до воскресенья: срок по-прежнему от пятницы, но уже прошёл.
    func testInboxPhraseParsedLater() throws {
        let later = TestCalendar.date("2026-10-18 12:00")
        let draft = try AIParser.parse(reminder(due: "2026-10-17T09:00:00+03:00"), reference: now, now: later,
                                       defaults: defaults, calendar: TestCalendar.moscow).drafts[0]

        XCTAssertEqual(draft.due, TestCalendar.date("2026-10-17 09:00"))
        XCTAssertEqual(draft.warning, "Время уже прошло")
    }

    func testTagsCleaned() {
        XCTAssertEqual(AIParser.tags(["#Школа", " школа ", "", "ресейл", "сервер", "лишний"]), ["школа", "ресейл", "сервер"])
        XCTAssertEqual(AIParser.tags("школа, сервер"), ["школа", "сервер"])
        XCTAssertEqual(AIParser.tags(nil), [])
    }
}
