import Foundation
import SwiftData

/// Папка для идей и заметок. Папки вкладываются друг в друга (до 3 уровней) через parentID —
/// без @Relationship, так проще и безопаснее обновлять базу. Дела в папки не кладутся.
@Model
final class Folder {
    @Attribute(.unique) var uid: UUID = UUID()
    var name: String = ""
    var colorRaw: String = FolderColor.blue.rawValue
    var symbol: String = FolderSymbol.all[0]
    /// nil — верхний уровень.
    var parentID: UUID?
    var sortIndex: Int = 0
    var createdAt: Date = Date()

    init(name: String, color: FolderColor = .blue, symbol: String = FolderSymbol.all[0], parentID: UUID? = nil,
         sortIndex: Int = 0, createdAt: Date = Date()) {
        self.uid = UUID()
        self.name = name
        self.colorRaw = color.rawValue
        self.symbol = symbol
        self.parentID = parentID
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }

    var color: FolderColor {
        get { FolderColor(rawValue: colorRaw) ?? .blue }
        set { colorRaw = newValue.rawValue }
    }

    var node: FolderNode {
        FolderNode(id: uid, name: name, parentID: parentID, sortIndex: sortIndex, createdAt: createdAt)
    }
}

/// 8 цветов папки.
enum FolderColor: String, CaseIterable, Identifiable, Codable {
    case blue, green, orange, red, purple, pink, yellow, gray

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: return "Синий"
        case .green: return "Зелёный"
        case .orange: return "Оранжевый"
        case .red: return "Красный"
        case .purple: return "Фиолетовый"
        case .pink: return "Розовый"
        case .yellow: return "Жёлтый"
        case .gray: return "Серый"
        }
    }
}

/// Значки папки (SF Symbols).
enum FolderSymbol {
    static let all = ["folder", "briefcase", "lightbulb", "graduationcap", "cart", "gamecontroller", "star", "heart"]
}
