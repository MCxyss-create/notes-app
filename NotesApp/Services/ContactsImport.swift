import Contacts
import Foundation
import SwiftData

/// Дни рождения из Контактов iPhone. Контакты остаются на телефоне — никуда не отправляются.
/// Ограниченный доступ (выбраны только некоторые контакты) тоже работает: берём, что разрешено.
@MainActor
enum ContactsImport {
    /// Спрашивает доступ, берёт ДР и обновляет календарь без дублей. Возвращает строку для экрана.
    static func run(context: ModelContext) async -> String {
        do {
            guard try await CNContactStore().requestAccess(for: .contacts) else {
                return "Нет доступа к Контактам — разреши в настройках iPhone."
            }
        } catch {
            return "Нет доступа к Контактам — разреши в настройках iPhone."
        }

        let found = await Task.detached { fetchBirthdays() }.value
        guard !found.isEmpty else { return "В Контактах нет дней рождения." }

        let events = (try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? []
        var known = events.map {
            ContactBirthday.Known(uid: $0.uid, contactID: $0.contactID, title: $0.title, month: $0.month, day: $0.day)
        }
        var added = 0
        var updated = 0
        for birthday in found {
            switch birthday.action(existing: known) {
            case .add:
                let event = CalendarEvent(type: .birthday, title: birthday.title, month: birthday.month,
                                          day: birthday.day, year: birthday.year, source: .contacts,
                                          contactID: birthday.contactID)
                context.insert(event)
                known.append(ContactBirthday.Known(uid: event.uid, contactID: birthday.contactID,
                                                   title: birthday.title, month: birthday.month, day: birthday.day))
                added += 1
            case .update(let uid):
                guard let event = events.first(where: { $0.uid == uid }) else { continue }
                if event.title != birthday.title || event.month != birthday.month || event.day != birthday.day
                    || (birthday.year != nil && event.year != birthday.year) {
                    event.title = birthday.title
                    event.month = birthday.month
                    event.day = birthday.day
                    event.year = birthday.year ?? event.year
                    updated += 1
                }
            case .skip:
                break
            }
        }
        try? context.save()
        if added == 0 && updated == 0 {
            return "Новых дней рождения нет — все \(found.count) уже в календаре."
        }
        return "Добавлено: \(added), обновлено: \(updated)."
    }

    /// Все контакты с днём рождения. Долго — поэтому не на главном потоке.
    nonisolated private static func fetchBirthdays() -> [ContactBirthday] {
        let keys = [CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey,
                    CNContactBirthdayKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var result: [ContactBirthday] = []
        try? CNContactStore().enumerateContacts(with: request) { contact, _ in
            if let birthday = ContactBirthday.make(contactID: contact.identifier, givenName: contact.givenName,
                                                   familyName: contact.familyName, nickname: contact.nickname,
                                                   birthday: contact.birthday) {
                result.append(birthday)
            }
        }
        return result
    }
}
