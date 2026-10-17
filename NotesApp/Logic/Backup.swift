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
}

/// Файл резервной копии: все записи одним JSON.
struct BackupFile: Codable {
    var app: String
    var version: Int
    var exportedAt: Date
    var items: [BackupItem]
}

enum Backup {
    static let appName = "Мысли"
    static let version = 1

    static func encode(_ items: [BackupItem], exportedAt: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(BackupFile(app: appName, version: version, exportedAt: exportedAt, items: items))
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

    /// «Мысли-2026-10-17.json».
    static func fileName(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        "\(appName)-\(SummaryPlanner.dayKey(date, calendar: calendar)).json"
    }
}
