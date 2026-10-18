import Foundation

/// Срок бесплатной подписи (iloader, бесплатный Apple ID) — 7 дней. Дата лежит в embedded.mobileprovision.
enum ProvisionInfo {
    /// nil — сборка без подписи (например, в GitHub) или файла нет.
    static let expirationDate: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return expiration(fromProfile: data)
    }()

    /// Профиль — подписанный контейнер, внутри которого лежит обычный plist. Достаём его и читаем ExpirationDate.
    static func expiration(fromProfile data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            return nil
        }
        return plist["ExpirationDate"] as? Date
    }
}

/// Напоминание переустановить приложение до того, как кончится подпись.
enum ResignPlanner {
    static let id = "resign-reminder"

    /// За сутки до конца; если сутки уже прошли — за 2 часа.
    static func plan(expiration: Date?, now: Date) -> PlannedNotification? {
        guard let expiration, expiration > now else { return nil }
        var fire = expiration.addingTimeInterval(-24 * 3600)
        if fire <= now {
            fire = expiration.addingTimeInterval(-2 * 3600)
        }
        guard fire > now else { return nil }
        return PlannedNotification(
            id: id,
            date: fire,
            title: "Пора переустановить «Мысли»",
            body: "Подпись кончится \(DateText.short(expiration, now: fire).lowercasedFirst). "
                + "Подключи iPhone к компьютеру: iloader → Import IPA — записи сохранятся."
        )
    }

    /// Плашка в ленте, когда до конца подписи меньше двух дней.
    static func needsBanner(expiration: Date?, now: Date) -> Bool {
        guard let expiration else { return false }
        return expiration.timeIntervalSince(now) < 2 * 86_400
    }
}
