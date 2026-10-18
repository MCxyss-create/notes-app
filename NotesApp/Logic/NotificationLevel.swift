import Foundation
import UserNotifications

/// Насколько настойчиво iOS показывает уведомление.
/// «Срочные» (Time Sensitive) пробивают Фокус и «Не беспокоить» и дольше держатся на экране
/// блокировки. Без разрешения в подписи iOS просто покажет их как обычные.
enum NotificationLevel {
    /// Проверочное уведомление из настроек.
    static let testPrefix = "test-"

    /// Дела, переподпись и проверочное — срочные; сводки и всё прочее — обычные.
    static func `for`(id: String) -> UNNotificationInterruptionLevel {
        if id.hasPrefix(NotificationPlanner.idPrefix) || id == ResignPlanner.id || id.hasPrefix(testPrefix) {
            return .timeSensitive
        }
        return .active
    }
}
