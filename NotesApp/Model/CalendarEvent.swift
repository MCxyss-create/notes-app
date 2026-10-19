import Foundation
import SwiftData

/// Дата в календаре, которая повторяется каждый год: день рождения, годовщина, своя дата.
/// Праздники РФ сюда не пишутся — они считаются в коде (`RussianHolidays`).
@Model
final class CalendarEvent {
    @Attribute(.unique) var uid: UUID = UUID()
    /// Для ДР — имя: «Лёша».
    var title: String = ""
    var typeRaw: String = EventType.birthday.rawValue
    var month: Int = 1
    var day: Int = 1
    /// Год рождения или события — необязательно. Есть — показываем возраст и «N лет».
    var year: Int?
    var note: String?
    /// За сколько дней напомнить: 0 — в день, 1, 3, 7.
    var remindDays: [Int] = [0, 1]
    /// Время напоминания, минуты от полуночи. nil — из настроек («Время для «завтра»», 09:00).
    var remindMinutes: Int?
    var sourceRaw: String = EventSource.manual.rawValue
    /// Контакт iPhone, из которого взят ДР: повторный импорт обновляет, а не дублирует.
    var contactID: String?
    var createdAt: Date = Date()

    init(type: EventType, title: String, month: Int, day: Int, year: Int? = nil, note: String? = nil,
         remindDays: [Int] = [0, 1], remindMinutes: Int? = nil, source: EventSource = .manual,
         contactID: String? = nil, createdAt: Date = Date()) {
        self.uid = UUID()
        self.typeRaw = type.rawValue
        self.title = title
        self.month = month
        self.day = day
        self.year = year
        self.note = note
        self.remindDays = remindDays
        self.remindMinutes = remindMinutes
        self.sourceRaw = source.rawValue
        self.contactID = contactID
        self.createdAt = createdAt
    }

    var type: EventType {
        get { EventType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    var source: EventSource {
        get { EventSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var entry: CalendarEntry {
        CalendarEntry(id: uid.uuidString, title: title, type: type, month: month, day: day, year: year,
                      remindDays: remindDays, remindMinutes: remindMinutes)
    }

    var draft: EventDraft {
        EventDraft(type: type, title: title, month: month, day: day, year: year, note: note,
                   remindDays: remindDays, remindMinutes: remindMinutes)
    }

    /// Записать правки из формы.
    func apply(_ draft: EventDraft) {
        type = draft.type
        title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        month = draft.month
        day = draft.day
        year = draft.year
        note = draft.note.flatMap { $0.isEmpty ? nil : $0 }
        remindDays = draft.remindDays
        remindMinutes = draft.remindMinutes
    }
}

/// Вид события.
enum EventType: String, CaseIterable, Identifiable, Codable {
    case birthday
    case anniversary
    case holiday
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .birthday: return "День рождения"
        case .anniversary: return "Годовщина"
        case .holiday: return "Праздник"
        case .other: return "Другое"
        }
    }

    var symbol: String {
        switch self {
        case .birthday: return "gift"
        case .anniversary: return "heart"
        case .holiday: return "star"
        case .other: return "calendar"
        }
    }
}

/// Откуда событие: руками (и через ИИ) или из Контактов.
enum EventSource: String, Codable {
    case manual
    case contacts
}
