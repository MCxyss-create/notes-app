import XCTest
@testable import NotesApp

final class AIPromptAndClientTests: XCTestCase {
    /// В промт подставлены дата, время, день недели, пояс и значения по умолчанию.
    func testPromptHasNowZoneAndDefaults() {
        let prompt = AIPrompt.system(now: TestCalendar.date("2026-10-16 22:24"), calendar: TestCalendar.moscow,
                                     defaultHour: 9, defaultMinute: 0, defaultBefore: 15)

        XCTAssertTrue(prompt.contains("Сейчас: 2026-10-16 22:24, пятница."))
        XCTAssertTrue(prompt.contains("Europe/Moscow (UTC+03:00)"))
        XCTAssertTrue(prompt.contains("- завтра, 2026-10-17, суббота"))
        XCTAssertTrue(prompt.contains("- 2026-10-19, понедельник"))
        XCTAssertTrue(prompt.contains("- 2026-10-23, пятница"))
        XCTAssertTrue(prompt.contains("Назван день без времени → 09:00, time_given=false"))
        XCTAssertTrue(prompt.contains("Не сказано → 15."))
        // DeepSeek требует слово json в промте для response_format json_object.
        XCTAssertTrue(prompt.contains("json"))
    }

    func testRequestBody() throws {
        let config = AIConfig(endpoint: try XCTUnwrap(AIConfig.url(from: "")), model: "deepseek-flash", apiKey: "sk-test")
        let request = try DeepSeekClient.makeRequest(config: config, system: "правила json", phrase: "завтра подойти к учителю")

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "deepseek-flash")
        XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "disabled")
        XCTAssertEqual((body["response_format"] as? [String: String])?["type"], "json_object")
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.map { $0["role"] ?? "" }, ["system", "user"])
        XCTAssertEqual(messages[1]["content"], "завтра подойти к учителю")
    }

    func testContentAndErrorFromResponse() throws {
        let ok = Data(#"{"choices":[{"message":{"role":"assistant","content":"{\"items\":[]}"}}]}"#.utf8)
        XCTAssertEqual(try DeepSeekClient.content(from: ok), #"{"items":[]}"#)

        let empty = Data(#"{"choices":[{"message":{"content":""}}]}"#.utf8)
        XCTAssertThrowsError(try DeepSeekClient.content(from: empty))

        let failed = Data(#"{"error":{"message":"Model Not Exist","type":"invalid_request_error"}}"#.utf8)
        XCTAssertEqual(DeepSeekClient.errorMessage(from: failed), "Model Not Exist")
    }

    func testEndpointFromSettings() {
        XCTAssertEqual(AIConfig.url(from: " ")?.absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(AIConfig.url(from: "https://api.deepseek.com/")?.absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(AIConfig.url(from: "my.server.ru/v1")?.absoluteString, "https://my.server.ru/v1/chat/completions")
        XCTAssertNil(AIConfig.url(from: "ftp://example.com"))
    }

    func testErrorMessages() {
        XCTAssertEqual(AIError.http(401, nil).message, "Ключ DeepSeek не подошёл (401)")
        XCTAssertEqual(AIError.http(402, "Insufficient Balance").message, "На балансе DeepSeek закончились деньги (402)")
        XCTAssertEqual(AIError.http(400, "Model Not Exist").message, "DeepSeek не принял запрос (400): Model Not Exist")
        XCTAssertTrue(AIError.http(503, nil).isTemporary)
        XCTAssertFalse(AIError.http(401, nil).isTemporary)
        XCTAssertEqual(AIError.from(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(AIError.from(URLError(.timedOut)), .offline)
    }
}
