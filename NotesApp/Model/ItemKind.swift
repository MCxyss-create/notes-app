import Foundation

/// Вид записи.
enum ItemKind: String, CaseIterable, Identifiable, Codable {
    case reminder
    case idea
    case note

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reminder: return "Напоминание"
        case .idea: return "Идея"
        case .note: return "Заметка"
        }
    }

    var symbol: String {
        switch self {
        case .reminder: return "bell"
        case .idea: return "lightbulb"
        case .note: return "note.text"
        }
    }
}

/// Повтор напоминания (логика повторов — этап 3).
enum RepeatRule: String, CaseIterable, Codable {
    case daily
    case weekly
    case monthly
}

/// Откуда взялась запись.
enum ItemSource: String, Codable {
    case manual
    case ai
}
