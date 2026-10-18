import SwiftUI

/// Проверка этапа 2: 8 контрольных фраз и 4 команды через DeepSeek.
/// «Сейчас» для них — пятница 16.10.2026, 22:24 по Москве, как в таблице плана.
struct AICheckView: View {
    @State private var results: [String: AIControlCheck.Outcome] = [:]
    @State private var running = false
    @State private var problem: String?

    private var total: Int {
        AIControlCheck.cases.count + AIControlCheck.commandCases.count + AIControlCheck.folderCases.count
    }
    private var passed: Int { results.values.filter(\.passed).count }

    var body: some View {
        List {
            Section {
                if running {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Проверяю… \(results.count) из \(total)")
                    }
                } else if !results.isEmpty {
                    Text("Верно \(passed) из \(total)")
                        .font(.headline)
                        .foregroundStyle(passed == total ? Color.green : Color.orange)
                }
                if let problem {
                    Text(problem)
                        .foregroundStyle(Color.red)
                }
                Button(results.isEmpty ? "Запустить проверку" : "Запустить ещё раз") {
                    Task { await run() }
                }
                .disabled(running)
            } footer: {
                Text("Фразы разбираются так, будто сейчас пятница, 16 октября 2026, 22:24 по Москве. Это \(total) запросов к DeepSeek — меньше цента.")
            }

            Section("Фразы") {
                ForEach(AIControlCheck.cases) { check in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 8) {
                            mark(results[check.phrase])
                            Text(check.phrase)
                        }
                        Text("Надо: \(check.summary)")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                        if let outcome = results[check.phrase] {
                            Text(outcome.details)
                                .font(.caption)
                                .foregroundStyle(outcome.passed ? Color.secondary : Color.red)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                ForEach(AIControlCheck.commandCases) { check in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 8) {
                            mark(results[check.phrase])
                            Text(check.phrase)
                        }
                        Text("Надо: \(check.summary)")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                        if let outcome = results[check.phrase] {
                            Text(outcome.details)
                                .font(.caption)
                                .foregroundStyle(outcome.passed ? Color.secondary : Color.red)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Команды")
            } footer: {
                Text("Будто в приложении уже есть: «Подойти к учителю» (сб 09:00), «Позвонить маме» (сб 18:00), «Сдать пробник» (пн 13:30), заметка про размер ноги и идея про бота.")
            }

            Section {
                ForEach(AIControlCheck.folderCases) { check in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 8) {
                            mark(results[check.phrase])
                            Text(check.phrase)
                        }
                        Text("Надо: \(check.summary)")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                        if let outcome = results[check.phrase] {
                            Text(outcome.details)
                                .font(.caption)
                                .foregroundStyle(outcome.passed ? Color.secondary : Color.red)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Папки")
            } footer: {
                Text("Будто уже есть папки «Проекты / VPN», «Шопинг», «Школа» и те же записи, что для команд.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Проверка разбора")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func mark(_ outcome: AIControlCheck.Outcome?) -> some View {
        if let outcome {
            Image(systemName: outcome.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(outcome.passed ? Color.green : Color.red)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(Color.secondary)
        }
    }

    private func run() async {
        problem = nil
        let config: AIConfig
        do {
            config = try AISettings.config()
        } catch {
            problem = AIError.from(error).message
            return
        }
        running = true
        results = [:]
        for check in AIControlCheck.cases {
            results[check.phrase] = await AIControlCheck.run(check, config: config)
        }
        for check in AIControlCheck.commandCases {
            results[check.phrase] = await AIControlCheck.run(check, config: config)
        }
        for check in AIControlCheck.folderCases {
            results[check.phrase] = await AIControlCheck.run(check, config: config)
        }
        running = false
    }
}
