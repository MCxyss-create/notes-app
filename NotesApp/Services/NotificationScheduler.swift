import Foundation
import SwiftData
import UserNotifications

/// Общая база записей: нужна кнопкам в уведомлениях, когда iOS запускает приложение в фоне.
@MainActor
enum AppModel {
    static var container: ModelContainer?

    /// База для команд Siri и Кнопки действия: iOS может запустить приложение ради них без окна.
    static func sharedContainer() -> ModelContainer {
        if let container { return container }
        do {
            let made = try ModelContainer(for: Item.self, InboxEntry.self,
                                          configurations: ModelConfiguration(isStoredInMemoryOnly: false))
            container = made
            return made
        } catch {
            fatalError("Не удалось открыть базу записей: \(error)")
        }
    }
}

/// Пересчитывает все уведомления: дела, сводки, напоминание о переподписи.
@MainActor
enum NotificationScheduler {
    @discardableResult
    static func rescheduleAll(items: [Item], now: Date = Date()) -> Task<Void, Never> {
        let reminders = items
            .filter { $0.kind == .reminder }
            .map { ReminderInput(item: $0) }
        var plan = NotificationPlanner.plan(reminders, now: now)
        plan += SummaryPlanner.plan(reminders, now: now, settings: SummarySettings.current)
        if let resign = ResignPlanner.plan(expiration: ProvisionInfo.expirationDate, now: now) {
            plan.append(resign)
        }
        return NotificationService.shared.reschedule(plan)
    }
}

/// Кнопки в уведомлении о деле.
enum NotificationActionID {
    static let category = "reminder"
    static let repeatCategory = "reminder-repeat"
    static let done = "done"
    static let hour = "snooze-hour"
    static let tomorrow = "snooze-tomorrow"

    static var categories: Set<UNNotificationCategory> {
        let done = UNNotificationAction(identifier: Self.done, title: "Готово", options: [],
                                        icon: UNNotificationActionIcon(systemImageName: "checkmark"))
        let hour = UNNotificationAction(identifier: Self.hour, title: "Через час", options: [],
                                        icon: UNNotificationActionIcon(systemImageName: "clock"))
        let tomorrow = UNNotificationAction(identifier: Self.tomorrow, title: "Завтра", options: [],
                                            icon: UNNotificationActionIcon(systemImageName: "sunrise"))
        return [
            UNNotificationCategory(identifier: category, actions: [done, hour, tomorrow], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: repeatCategory, actions: [done], intentIdentifiers: [], options: []),
        ]
    }
}

/// Нажали кнопку в уведомлении: меняем запись и пересчитываем уведомления, не открывая приложение.
@MainActor
enum NotificationActions {
    static func handle(action: String, uid: String) async {
        guard let container = AppModel.container, let id = UUID(uuidString: uid) else { return }
        let context = container.mainContext
        guard let items = try? context.fetch(FetchDescriptor<Item>()),
              let item = items.first(where: { $0.uid == id }) else { return }

        let now = Date()
        switch action {
        case NotificationActionID.done:
            ItemActions.complete(item, now: now)
        case NotificationActionID.hour:
            ItemActions.snooze(item, .hour, now: now)
        case NotificationActionID.tomorrow:
            ItemActions.snooze(item, .tomorrow, now: now)
        default:
            return
        }
        try? context.save()
        await NotificationScheduler.rescheduleAll(items: items, now: now).value
    }
}
