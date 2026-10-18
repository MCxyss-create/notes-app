import Foundation

/// Одна запись в резервной копии.
struct BackupItem: Codable, Equatable {
    var uid: UUID
    var kind: String
    var title: String
    var body: String?
    var createdAt: Date
    var dueAt: Date?
    var timeGiven: Bool
    var remindBeforeMin: Int?
    var repeatRule: String?
    var isDone: Bool
    var doneAt: Date?
    var tags: [String]
    var isPinned: Bool
    var rawInput: String?
    var source: String
    /// С версии 2. В старых копиях нет — запись «Без папки».
    var folderID: UUID? = nil
}

/// Одна папка в резервной копии (с версии 2).
struct BackupFolder: Codable, Equatable {
    var uid: UUID
    var name: String
    var color: String
    var symbol: String
    var parentID: UUID?
    var sortIndex: Int
    var createdAt: Date
}

/// Файл резервной копии: все записи одним JSON. Версия 2 — ещё и папки.
struct BackupFile: Codable {
    var app: String
    var version: Int
    var exportedAt: Date
    var items: [BackupItem]
    var folders: [BackupFolder]? = nil
}

enum Backup {
    static let appName = "Мысли"
    static let version = 2

    static func encode(_ items: [BackupItem], folders: [BackupFolder] = [], exportedAt: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(BackupFile(app: appName, version: version, exportedAt: exportedAt, items: items,
                                             folders: folders))
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupFile.self, from: data)
    }

    /// Что добавить из копии: записи, которых ещё нет (по uid). Существующие не трогаем.
    static func newItems(in file: BackupFile, existing: Set<UUID>) -> [BackupItem] {
        var seen = existing
        var result: [BackupItem] = []
        for item in file.items where !seen.contains(item.uid) {
            result.append(item)
            seen.insert(item.uid)
        }
        return result
    }

    /// Какие папки добавить: тех, что уже есть (по uid), не трогаем, повторы в файле не двоим.
    static func newFolders(in file: BackupFile, existing: Set<UUID>) -> [BackupFolder] {
        var seen = existing
        var result: [BackupFolder] = []
        for folder in file.folders ?? [] where !seen.contains(folder.uid) {
            result.append(folder)
            seen.insert(folder.uid)
        }
        return result
    }

    /// «Мысли-2026-10-17.json».
    static func fileName(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        "\(appName)-\(SummaryPlanner.dayKey(date, calendar: calendar)).json"
    }
}
