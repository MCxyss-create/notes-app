import AppIntents

/// «Записать мысль»: Siri или Кнопка действия спрашивает «Что записать?» и сохраняет,
/// не открывая приложение.
struct CaptureThoughtIntent: AppIntent {
    static let title: LocalizedStringResource = "Записать мысль"
    static let description = IntentDescription("Записывает фразу, не открывая приложение. ИИ сам поймёт: дело, идея или заметка.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Что записать", requestValueDialog: IntentDialog("Что записать?"))
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await QuickCapture.save(text)
        return .result(dialog: "\(answer)")
    }
}

/// «Надиктовать»: открывает приложение и сразу включает микрофон.
struct DictateThoughtIntent: AppIntent {
    static let title: LocalizedStringResource = "Надиктовать мысль"
    static let description = IntentDescription("Открывает «Мысли» и сразу включает микрофон.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickLaunch.shared.request(.dictate)
        return .result()
    }
}

/// «Дела на сегодня»: Siri отвечает, что сегодня и сколько просрочено.
struct TodayTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "Дела на сегодня"
    static let description = IntentDescription("Говорит, какие дела сегодня и сколько просрочено.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = QuickCapture.todayText()
        return .result(dialog: "\(answer)")
    }
}

/// Готовые команды: появляются в приложении «Команды», в Siri и в настройках Кнопки действия.
struct MysliShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureThoughtIntent(),
            phrases: [
                "\(.applicationName), запиши мысль",
                "Запиши в \(.applicationName)",
                "Новая мысль в \(.applicationName)",
            ],
            shortTitle: "Записать мысль",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: DictateThoughtIntent(),
            phrases: [
                "\(.applicationName), надиктовать",
                "Надиктуй в \(.applicationName)",
            ],
            shortTitle: "Надиктовать",
            systemImageName: "mic"
        )
        AppShortcut(
            intent: TodayTasksIntent(),
            phrases: [
                "\(.applicationName), что сегодня",
                "Дела на сегодня в \(.applicationName)",
            ],
            shortTitle: "Дела на сегодня",
            systemImageName: "list.bullet"
        )
    }
}
