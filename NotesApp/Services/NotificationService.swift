import Foundation
import UserNotifications

/// Показывает уведомления, даже когда приложение открыто.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Кнопки «Готово / Через час / Завтра». iOS может запустить приложение ради них в фоне.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        guard action != UNNotificationDefaultActionIdentifier,
              action != UNNotificationDismissActionIdentifier,
              let uid = response.notification.request.content.userInfo["uid"] as? String else { return }
        await NotificationActions.handle(action: action, uid: uid)
    }
}

/// Локальные уведомления: ставит их сам телефон, сервер не нужен.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let delegate = NotificationDelegate()
    private var queue: Task<Void, Never>?

    private init() {}

    func configure() {
        center.delegate = delegate
        center.setNotificationCategories(NotificationActionID.categories)
    }

    func status() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// «Срочные»: включены, выключены в настройках iPhone или не разрешены подписью.
    func timeSensitive() async -> UNNotificationSetting {
        await center.notificationSettings().timeSensitiveSetting
    }

    /// Спрашивает разрешение, если ещё не спрашивали. true — уведомления разрешены.
    @discardableResult
    func requestIfNeeded() async -> Bool {
        switch await status() {
        case .notDetermined:
            let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted ?? false
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func pendingCount() async -> Int {
        await center.pendingNotificationRequests().count
    }

    /// Убирает старые уведомления (дела, сводки, переподпись) и ставит новые.
    /// Вызовы идут строго по очереди; результат можно дождаться через `.value`.
    @discardableResult
    func reschedule(_ planned: [PlannedNotification]) -> Task<Void, Never> {
        let previous = queue
        let task = Task { [center] in
            await previous?.value
            let pending = await center.pendingNotificationRequests()
            let old = pending.map(\.identifier).filter { id in
                NotificationPlanner.managedPrefixes.contains { id.hasPrefix($0) }
            }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for p in planned {
                try? await center.add(Self.request(for: p))
            }
        }
        queue = task
        return task
    }

    /// Проверочное уведомление через N секунд.
    func scheduleTest(after seconds: TimeInterval) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Проверка уведомлений"
        content.body = "Всё работает: уведомления приходят."
        content.sound = .default
        let id = "\(NotificationLevel.testPrefix)\(UUID().uuidString)"
        content.interruptionLevel = NotificationLevel.for(id: id)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try await center.add(request)
    }

    private static func request(for p: PlannedNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = p.title
        content.body = p.body
        content.sound = .default
        content.interruptionLevel = NotificationLevel.for(id: p.id)
        if let itemID = p.itemID {
            content.categoryIdentifier = p.repeating ? NotificationActionID.repeatCategory : NotificationActionID.category
            content.userInfo = ["uid": itemID.uuidString]
        }
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: p.date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(identifier: p.id, content: content, trigger: trigger)
    }
}
