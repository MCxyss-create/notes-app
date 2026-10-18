import XCTest
@testable import NotesApp

/// Живая проверка 8 контрольных фраз через настоящий DeepSeek.
/// Работает, только если в GitHub добавлен секрет DEEPSEEK_API_KEY, иначе пропускается.
/// Сборку не роняет: итог пишет строками AI-CHECK, их показывает страница запуска.
final class AILiveCheckTests: XCTestCase {
    func testControlPhrasesWithDeepSeek() async throws {
        let key = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] ?? ""
        try XCTSkipIf(key.isEmpty, "Нет секрета DEEPSEEK_API_KEY — живая проверка пропущена")

        let config = AIConfig(endpoint: try XCTUnwrap(AIConfig.url(from: "")), model: AIConfig.defaultModel, apiKey: key)
        var passed = 0
        for check in AIControlCheck.cases {
            let outcome = await AIControlCheck.run(check, config: config)
            if outcome.passed { passed += 1 }
            print("AI-CHECK \(outcome.passed ? "✅" : "❌") «\(check.phrase)» → \(outcome.details)")
        }
        for check in AIControlCheck.commandCases {
            let outcome = await AIControlCheck.run(check, config: config)
            if outcome.passed { passed += 1 }
            print("AI-CHECK \(outcome.passed ? "✅" : "❌") команда «\(check.phrase)» → \(outcome.details)")
        }
        for check in AIControlCheck.folderCases {
            let outcome = await AIControlCheck.run(check, config: config)
            if outcome.passed { passed += 1 }
            print("AI-CHECK \(outcome.passed ? "✅" : "❌") папки «\(check.phrase)» → \(outcome.details)")
        }
        let total = AIControlCheck.cases.count + AIControlCheck.commandCases.count + AIControlCheck.folderCases.count
        print("AI-CHECK Итог: верно \(passed) из \(total)")
    }
}
