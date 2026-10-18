import XCTest
@testable import NotesApp

/// Голосовые команды: список записей в промте, разбор "changes" и "found", 4 контрольные команды.
final class VoiceCommandTests: XCTestCase {
    private let calendar = AIControlCheck.calendar
    private let now = AIControlCheck.now
    private let defaults = AIControlCheck.defaults
    private var known: [AIKnownItem] { AIControlCheck.commandItems }

    private func parse(_ json: String, known: [AIKnownItem]? = nil) throws -> AIResult {
        try AIParser.parse(json, reference: now, now: now, defaults: defaults, calendar: calendar,
                           known: known ?? self.known)
    }

    private func text(_ date: Date?) -> String? {
        date.map(AIControlCheck.text)
    }

    func testRefIsStableUIDPrefix() {
        XCTAssertEqual(known.map(\.ref), ["a1b2c3", "d4e5f6", "0c9d8e", "7f6e5d", "b7c8d9"])
    }

    func testPromptListsRecordsOnlyWhenTheyExist() {
        let plain = AIPrompt.system(now: now, calendar: calendar, defaultHour: 9, defaultMinute: 0, defaultBefore: 15)
        XCTAssertFalse(plain.contains("Записи, которые уже есть"))
        XCTAssertTrue(plain.contains("Слова-паразиты убирай"))

        let withList = AIPrompt.system(now: now, calendar: calendar, defaultHour: 9, defaultMinute: 0,
                                       defaultBefore: 15, known: known)
        XCTAssertTrue(withList.contains("- a1b2c3 | дело | Подойти к учителю | 2026-10-17 09:00"))
        XCTAssertTrue(withList.contains("- 7f6e5d | заметка | Размер ноги: Nike 43, Adidas 42.5"))
        XCTAssertTrue(withList.contains("\"op\":\"move\""))
        XCTAssertTrue(withList.contains("\"found\""))
    }

    func testPromptPicksNearestOpenRecords() {
        let base = TestCalendar.date("2026-10-16 12:00")
        var list: [AIKnownItem] = []
        for n in 0..<50 {
            list.append(AIKnownItem(uid: UUID(), kind: .reminder, title: "Дело \(n)",
                                    due: base.addingTimeInterval(Double(50 - n) * 3600)))
        }
        list.append(AIKnownItem(uid: UUID(), kind: .reminder, title: "Без срока"))
        for n in 0..<25 {
            list.append(AIKnownItem(uid: UUID(), kind: .idea, title: "Идея \(n)", createdAt: base.addingTimeInterval(Double(n))))
        }
        let picked = AIContext.forPrompt(list)
        XCTAssertEqual(picked.count, AIContext.reminderLimit + AIContext.otherLimit)
        XCTAssertEqual(picked.first?.title, "Дело 49")
        XCTAssertFalse(picked.contains { $0.title == "Без срока" })
        XCTAssertEqual(picked[AIContext.reminderLimit].title, "Идея 24")
    }

    func testDoneDeleteAndEdit() throws {
        let result = try parse("""
        {"items":[],"changes":[
          {"op":"done","id":"d4e5f6"},
          {"op":"delete","id":"#7F6E5D"},
          {"op":"edit","id":"b7c8d9","title":"Бот для учёта ресейла.","body":null},
          {"op":"done","id":"ffffff"},
          {"op":"fly","id":"a1b2c3"}
        ],"reply":"Готово."}
        """)
        XCTAssertTrue(result.drafts.isEmpty)
        XCTAssertEqual(result.changes.map(\.op), [.done, .delete, .edit])
        XCTAssertEqual(result.changes.map(\.target.title), ["Позвонить маме", "Размер ноги: Nike 43, Adidas 42.5",
                                                           "Бот для прибыли с ресейла"])
        XCTAssertEqual(result.changes[2].title, "Бот для учёта ресейла")
        XCTAssertFalse(result.answered)
    }

    /// «Перенеси на понедельник» без времени — остаётся прежнее 09:00 и «время подставлено».
    func testMoveToDayKeepsOldTime() throws {
        let result = try parse(#"{"items":[],"changes":[{"op":"move","id":"a1b2c3","due":"2026-10-19"}],"reply":"ок"}"#)
        let change = try XCTUnwrap(result.changes.first)
        XCTAssertEqual(text(change.due), "2026-10-19 09:00")
        XCTAssertFalse(change.timeGiven)
        XCTAssertNil(change.warning)

        let exam = try parse(#"{"changes":[{"op":"move","id":"0c9d8e","due":"2026-10-20T15:00:00+03:00","time_given":true}]}"#)
        XCTAssertEqual(text(exam.changes.first?.due), "2026-10-20 15:00")
        XCTAssertEqual(exam.changes.first?.timeGiven, true)
    }

    /// Заметку не переносят; срок в прошлом — с предупреждением.
    func testMoveChecks() throws {
        let note = try parse(#"{"changes":[{"op":"move","id":"7f6e5d","due":"2026-10-19T09:00:00+03:00"}]}"#)
        XCTAssertTrue(note.changes.isEmpty)

        let past = try parse(#"{"changes":[{"op":"move","id":"d4e5f6","due":"2026-10-16T20:00:00+03:00"}]}"#)
        XCTAssertEqual(text(past.changes.first?.due), "2026-10-17 20:00")
        XCTAssertNotNil(past.changes.first?.warning)

        let noDate = try parse(#"{"changes":[{"op":"move","id":"d4e5f6"}]}"#)
        XCTAssertTrue(noDate.changes.isEmpty)
    }

    func testQuestionAnswer() throws {
        let result = try parse(#"{"items":[],"changes":[],"found":["a1b2c3","d4e5f6","a1b2c3","zzzzzz"],"reply":"Завтра 2 дела."}"#)
        XCTAssertTrue(result.answered)
        XCTAssertEqual(result.found.map(\.title), ["Подойти к учителю", "Позвонить маме"])

        let nothing = try parse(#"{"items":[],"found":[],"reply":"Завтра дел нет."}"#)
        XCTAssertTrue(nothing.answered)
        XCTAssertTrue(nothing.found.isEmpty)
    }

    /// Старый ответ без команд разбирается как раньше; команды без списка записей — мимо.
    func testOldFormatAndNoKnownItems() throws {
        let old = try parse(#"{"items":[{"kind":"idea","title":"Бот"}],"reply":"Идея."}"#)
        XCTAssertEqual(old.drafts.count, 1)
        XCTAssertTrue(old.changes.isEmpty)
        XCTAssertFalse(old.answered)

        let orphan = try parse(#"{"items":[],"changes":[{"op":"done","id":"d4e5f6"}],"reply":"ок"}"#, known: [])
        XCTAssertTrue(orphan.changes.isEmpty)
    }

    func testFourControlCommands() throws {
        let ideal = [
            #"{"items":[],"changes":[{"op":"move","id":"a1b2c3","due":"2026-10-19T09:00:00+03:00","time_given":false}],"reply":"ок"}"#,
            #"{"items":[],"changes":[{"op":"done","id":"d4e5f6"}],"reply":"ок"}"#,
            #"{"items":[],"changes":[{"op":"delete","id":"7f6e5d"}],"reply":"ок"}"#,
            #"{"items":[],"changes":[],"found":["d4e5f6","a1b2c3"],"reply":"Завтра 2 дела."}"#,
        ]
        XCTAssertEqual(AIControlCheck.commandCases.count, 4)
        for (check, json) in zip(AIControlCheck.commandCases, ideal) {
            XCTAssertEqual(AIControlCheck.problems(try parse(json), expected: check), [], check.phrase)
        }

        // Вместо переноса создал новое напоминание — ошибка.
        let newReminder = #"{"items":[{"kind":"reminder","title":"Перенести учителя","due":"2026-10-19T09:00:00+03:00"}],"reply":"ок"}"#
        XCTAssertFalse(AIControlCheck.problems(try parse(newReminder), expected: AIControlCheck.commandCases[0]).isEmpty)

        // Перенёс не на тот день.
        let wrongDay = #"{"changes":[{"op":"move","id":"a1b2c3","due":"2026-10-23T09:00:00+03:00"}]}"#
        XCTAssertFalse(AIControlCheck.problems(try parse(wrongDay), expected: AIControlCheck.commandCases[0]).isEmpty)
    }

    func testSiriTextAfterCommands() throws {
        let result = try parse(#"{"changes":[{"op":"move","id":"a1b2c3","due":"2026-10-17T10:00:00+03:00"}]}"#)
        XCTAssertEqual(QuickCaptureText.changed(result.changes, skippedDelete: false, reply: "", now: now, calendar: calendar),
                       "Перенёс: Подойти к учителю, завтра, 10:00.")
        XCTAssertEqual(QuickCaptureText.changed([], skippedDelete: true, reply: "Удалил.", now: now, calendar: calendar),
                       "Удалить можно только в приложении.")
        XCTAssertEqual(QuickCaptureText.changed([], skippedDelete: false, reply: "Завтра 2 дела.", now: now, calendar: calendar),
                       "Завтра 2 дела.")
    }
}

final class VoicePauseTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    func testSendsAfterPauseInSpeech() {
        // Сказал, замолчал 1,7 с, тихо — уходит.
        XCTAssertEqual(VoicePause.decide(now: at(5), started: start, lastChange: at(3.3), lastLoud: at(3.3), hasText: true), .send)
        // Пауза короче 1,6 с — ждём.
        XCTAssertEqual(VoicePause.decide(now: at(5), started: start, lastChange: at(4), lastLoud: at(4), hasText: true), .listen)
        // Слов нет, но тянет «эээ» (громко) — ждём, пока слова не стоят 4 с.
        XCTAssertEqual(VoicePause.decide(now: at(5), started: start, lastChange: at(2.5), lastLoud: at(4.9), hasText: true), .listen)
        XCTAssertEqual(VoicePause.decide(now: at(7), started: start, lastChange: at(2.5), lastLoud: at(6.9), hasText: true), .send)
    }

    func testGivesUpWhenNothingSaid() {
        XCTAssertEqual(VoicePause.decide(now: at(7), started: start, lastChange: start, lastLoud: start, hasText: false), .listen)
        XCTAssertEqual(VoicePause.decide(now: at(8.5), started: start, lastChange: start, lastLoud: start, hasText: false), .giveUp)
        // Шумит голосом, а слов ещё нет (медленная сеть) — не бросаем.
        XCTAssertEqual(VoicePause.decide(now: at(9), started: start, lastChange: start, lastLoud: at(8), hasText: false), .listen)
        XCTAssertEqual(VoicePause.decide(now: at(56), started: start, lastChange: start, lastLoud: at(55.9), hasText: false), .giveUp)
    }

    func testLongestRecordingSends() {
        XCTAssertEqual(VoicePause.decide(now: at(55), started: start, lastChange: at(54.9), lastLoud: at(54.9), hasText: true), .send)
    }

    func testLevel() {
        XCTAssertEqual(VoicePause.level(rms: 0), 0)
        XCTAssertEqual(VoicePause.level(rms: 0.001), 0, accuracy: 0.001)   // −60 дБ
        XCTAssertEqual(VoicePause.level(rms: 0.1), 0.75, accuracy: 0.001)  // −20 дБ
        XCTAssertEqual(VoicePause.level(rms: 1), 1)
    }
}
