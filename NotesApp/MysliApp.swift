import SwiftUI
import SwiftData

@main
struct MysliApp: App {
    private let container: ModelContainer
    private let demo: DemoConfig?

    init() {
        let demo = DemoConfig.fromLaunchArguments()
        self.demo = demo

        // Демо-снимки и автотесты работают с базой в памяти, настоящие записи не трогают.
        let inMemory = demo != nil || AppEnvironment.isRunningTests
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
            container = try ModelContainer(for: Item.self, configurations: config)
        } catch {
            fatalError("Не удалось открыть базу записей: \(error)")
        }

        if let demo {
            DemoData.seed(into: container.mainContext, screen: demo.screen)
        }
        NotificationService.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView(demo: demo)
                .environment(\.locale, Locale(identifier: "ru_RU"))
        }
        .modelContainer(container)
    }
}
