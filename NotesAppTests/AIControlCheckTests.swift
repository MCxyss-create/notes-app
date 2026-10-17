import XCTest
@testable import NotesApp

/// 8 контрольных фраз из плана. Здесь — без сети: подставляем правильные ответы модели
/// и проверяем, что приложение их понимает, а проверка отличает верное от неверного.
final class AIControlCheckTests: XCTestCase {
    private func parse(_ json: String) throws -> [AIDraft] {
        try AIParser.parse(json, reference: AIControlCheck.now, now: AIControlCheck.now,
                           defaults: AIControlCheck.defaults, calendar: AIControlCheck.calendar).drafts
    }

    private func reminder(_ title: String, _ due: String, before: Int = 15, rule: String = "null") -> String {
        let ruleJSON = rule == "null" ? "null" : "\"\(rule)\""
        return #"{"kind":"reminder","title":"\#(title)","body":null,"due":"\#(due)","time_given":true,"remind_before_min":\#(before),"repeat":\#(ruleJSON),"tags":[]}"#
    }

    private func answer(_ items: String...) -> String {
        #"{"items":[\#(items.joined(separator: ","))],"reply":"ок"}"#
    }

    private var idealAnswers: [String] {
        [
            answer(reminder("Подойти к учителю", "2026-10-17T09:00:00+03:00")),
            answer(reminder("Забрать кроссовки с почты", "2026-10-23T15:00:00+03:00")),
            answer(reminder("Позвонить маме", "2026-10-17T00:24:00+03:00")),
            answer(#"{"kind":"idea","title":"Бот для прибыли с ресейла","due":null,"tags":["ресейл"]}"#),
            answer(#"{"kind":"note","title":"Размер ноги","body":"Nike 43, Adidas 42.5","due":null,"tags":[]}"#),
            answer(reminder("Оплатить сервер", "2026-10-17T19:00:00+03:00"),
                   reminder("Сдать пробник", "2026-10-17T09:00:00+03:00")),
            answer(reminder("Написать контрольную", "2026-10-19T08:30:00+03:00", before: 60)),
            answer(reminder("Тренировка", "2026-10-20T18:00:00+03:00", rule: "weekly")),
        ]
    }

    func testIdealAnswersPassAllEight() throws {
        XCTAssertEqual(AIControlCheck.cases.count, 8)
        for (check, json) in zip(AIControlCheck.cases, idealAnswers) {
            XCTAssertEqual(AIControlCheck.problems(try parse(json), expected: check.expected), [], check.phrase)
        }
    }

    /// Два дела в обратном порядке — тоже верно.
    func testOrderDoesNotMatter() throws {
        let check = AIControlCheck.cases[5]
        let json = answer(reminder("Сдать пробник", "2026-10-17T09:00:00+03:00"),
                          reminder("Оплатить сервер", "2026-10-17T19:00:00+03:00"))
        XCTAssertEqual(AIControlCheck.problems(try parse(json), expected: check.expected), [])
    }

    /// «в пятницу» → сегодняшняя пятница вместо следующей: проверка должна это поймать.
    func testWrongAnswersFail() throws {
        let friday = AIControlCheck.cases[1]
        let wrongDay = answer(reminder("Забрать кроссовки с почты", "2026-10-16T15:00:00+03:00"))
        XCTAssertFalse(AIControlCheck.problems(try parse(wrongDay), expected: friday.expected).isEmpty)

        let twoThings = AIControlCheck.cases[5]
        let onlyOne = answer(reminder("Оплатить сервер", "2026-10-17T19:00:00+03:00"))
        XCTAssertFalse(AIControlCheck.problems(try parse(onlyOne), expected: twoThings.expected).isEmpty)

        let weekly = AIControlCheck.cases[7]
        let noRepeat = answer(reminder("Тренировка", "2026-10-20T18:00:00+03:00"))
        XCTAssertFalse(AIControlCheck.problems(try parse(noRepeat), expected: weekly.expected).isEmpty)
    }
}
