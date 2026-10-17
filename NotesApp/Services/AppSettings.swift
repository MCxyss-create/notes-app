import Foundation

/// Ключи настроек в UserDefaults (через @AppStorage).
enum SettingsKeys {
    static let defaultHour = "defaultHour"
    static let defaultMinute = "defaultMinute"
    static let defaultBeforeMin = "defaultBeforeMin"
    /// Кнопка ✨ у поля ввода: разбирать фразу через ИИ.
    static let aiEnabled = "aiEnabled"
    static let aiEndpoint = "aiEndpoint"
    static let aiModel = "aiModel"
    /// Сводки: утром — что сегодня, вечером — что завтра. Время — минуты от полуночи.
    static let morningSummaryOn = "morningSummaryOn"
    static let morningSummaryMinutes = "morningSummaryMinutes"
    static let eveningSummaryOn = "eveningSummaryOn"
    static let eveningSummaryMinutes = "eveningSummaryMinutes"
}

extension SummarySettings {
    static var current: SummarySettings {
        let defaults = UserDefaults.standard
        let standard = SummarySettings.standard
        return SummarySettings(
            morningOn: defaults.object(forKey: SettingsKeys.morningSummaryOn) as? Bool ?? standard.morningOn,
            morningMinutes: defaults.object(forKey: SettingsKeys.morningSummaryMinutes) as? Int ?? standard.morningMinutes,
            eveningOn: defaults.object(forKey: SettingsKeys.eveningSummaryOn) as? Bool ?? standard.eveningOn,
            eveningMinutes: defaults.object(forKey: SettingsKeys.eveningSummaryMinutes) as? Int ?? standard.eveningMinutes
        )
    }
}

/// Значения настроек для кода вне экранов.
enum AppDefaults {
    static var hour: Int {
        UserDefaults.standard.object(forKey: SettingsKeys.defaultHour) as? Int ?? 9
    }

    static var minute: Int {
        UserDefaults.standard.object(forKey: SettingsKeys.defaultMinute) as? Int ?? 0
    }

    static var beforeMin: Int {
        UserDefaults.standard.object(forKey: SettingsKeys.defaultBeforeMin) as? Int ?? 15
    }
}

enum AppEnvironment {
    /// Приложение запущено автотестами в GitHub.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

enum AppInfo {
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version), сборка \(build)"
    }
}
