import Foundation

/// Ключи настроек в UserDefaults (через @AppStorage).
enum SettingsKeys {
    static let defaultHour = "defaultHour"
    static let defaultMinute = "defaultMinute"
    static let defaultBeforeMin = "defaultBeforeMin"
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
