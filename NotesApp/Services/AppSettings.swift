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
    /// Голос: открыл приложение — микрофон уже слушает.
    static let listenOnOpen = "listenOnOpen"
    /// Голос: замолчал — фраза уходит сама.
    static let voiceAutoSend = "voiceAutoSend"
    /// Резервная копия вместе с фото.
    static let backupWithPhotos = "backupWithPhotos"
    /// Календарь: показывать праздники РФ, напоминать о них, какие скрыты («02-14,12-31»).
    static let holidaysOn = "holidaysOn"
    static let holidayReminders = "holidayReminders"
    static let hiddenHolidays = "hiddenHolidays"
}

/// Что показать в календаре и о чём напоминать: свои события и праздники по настройкам.
enum CalendarSettings {
    static var holidaysOn: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.holidaysOn) as? Bool ?? true
    }

    static var holidayReminders: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.holidayReminders) as? Bool ?? false
    }

    static var hidden: Set<String> {
        RussianHolidays.hidden(from: UserDefaults.standard.string(forKey: SettingsKeys.hiddenHolidays) ?? "")
    }

    /// Время напоминания по умолчанию — «Время для «завтра»» из настроек, минуты от полуночи.
    static var defaultMinutes: Int {
        AppDefaults.hour * 60 + AppDefaults.minute
    }

    /// Всё, что видно в календаре: свои события и праздники (если включены и не скрыты).
    static func shown(_ events: [CalendarEntry]) -> [CalendarEntry] {
        holidaysOn ? events + RussianHolidays.entries(hidden: hidden) : events
    }

    /// О чём напоминать: свои события и праздники — только если «Напоминать о праздниках».
    static func reminded(_ events: [CalendarEntry]) -> [CalendarEntry] {
        holidaysOn && holidayReminders ? events + RussianHolidays.entries(hidden: hidden) : events
    }
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
