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
    }

    func status() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
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

    /// Убирает старые уведомления записей и ставит новые. Вызовы идут строго по очереди.
    func reschedule(_ planned: [PlannedNotification]) {
        let previous = queue
        queue = Task { [center] in
            await previous?.value
            let pending = await center.pendingNotificationRequests()
            let old = pending.map(\.identifier).filter { $0.hasPrefix(NotificationPlanner.idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for p in planned {
                try? await center.add(Self.request(for: p))
            }
        }
    }

    /// Проверочное уведомление через N секунд.
    func scheduleTest(after seconds: TimeInterval) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Проверка уведомлений"
        content.body = "Всё работает: уведомления приходят."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger)
        try await center.add(request)
    }

    private static func request(for p: PlannedNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = p.title
        content.body = p.body
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: p.date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(identifier: p.id, content: content, trigger: trigger)
    }
}
