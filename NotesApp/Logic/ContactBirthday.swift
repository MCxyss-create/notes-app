import Foundation

/// День рождения из контакта iPhone. Контакты никуда не отправляются — ни в сеть, ни в DeepSeek.
struct ContactBirthday: Equatable {
    let contactID: String
    let title: String
    let month: Int
    let day: Int
    let year: Int?

    /// Контакт → ДР: имя и фамилия (нет — прозвище), день и месяц обязательны, год — если указан.
    /// Без даты, с неверной датой или без имени — nil.
    static func make(contactID: String, givenName: String, familyName: String, nickname: String = "",
                     birthday: DateComponents?) -> ContactBirthday? {
        guard let birthday, let month = birthday.month, let day = birthday.day,
              CalendarMath.isValid(month: month, day: day) else { return nil }
        let full = [givenName, familyName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let name = full.isEmpty ? nickname.trimmingCharacters(in: .whitespacesAndNewlines) : full
        guard !name.isEmpty else { return nil }
        // Контакты хранят «без года» как 1604 — такой год не настоящий.
        let year = birthday.year.flatMap { (1800...2200).contains($0) ? $0 : nil }
        return ContactBirthday(contactID: contactID, title: name, month: month, day: day, year: year)
    }

    /// Событие, которое уже есть, — для решения при импорте.
    struct Known: Equatable {
        let uid: UUID
        let contactID: String?
        let title: String
        let month: Int
        let day: Int
    }

    enum Action: Equatable {
        case add
        case update(UUID)
        case skip
    }

    /// Повторный импорт обновляет событие того же контакта; своё событие с тем же именем и датой
    /// не дублируем; иначе — новое.
    func action(existing: [Known]) -> Action {
        if let same = existing.first(where: { $0.contactID == contactID }) {
            return .update(same.uid)
        }
        let key = SearchMatcher.normalize(title.trimmingCharacters(in: .whitespacesAndNewlines))
        if existing.contains(where: { $0.month == month && $0.day == day
            && SearchMatcher.normalize($0.title.trimmingCharacters(in: .whitespacesAndNewlines)) == key }) {
            return .skip
        }
        return .add
    }
}
