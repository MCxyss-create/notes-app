import SwiftUI
import UniformTypeIdentifiers

/// Файл копии для окна «Сохранить в Файлы».
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension BackupItem {
    init(item: Item) {
        self.init(
            uid: item.uid,
            kind: item.kindRaw,
            title: item.title,
            body: item.body,
            createdAt: item.createdAt,
            dueAt: item.dueAt,
            timeGiven: item.timeGiven,
            remindBeforeMin: item.remindBeforeMin,
            repeatRule: item.repeatRaw,
            isDone: item.isDone,
            doneAt: item.doneAt,
            tags: item.tags,
            isPinned: item.isPinned,
            rawInput: item.rawInput,
            source: item.sourceRaw,
            folderID: item.folderID
        )
    }

    func makeItem() -> Item {
        let item = Item(
            kind: ItemKind(rawValue: kind) ?? .note,
            title: title,
            body: body,
            createdAt: createdAt,
            dueAt: dueAt,
            timeGiven: timeGiven,
            remindBeforeMin: remindBeforeMin,
            repeatRule: repeatRule.flatMap { RepeatRule(rawValue: $0) },
            isDone: isDone,
            doneAt: doneAt,
            tags: tags,
            isPinned: isPinned,
            rawInput: rawInput,
            source: ItemSource(rawValue: source) ?? .manual,
            folderID: folderID
        )
        item.uid = uid
        return item
    }
}

extension BackupFolder {
    init(folder: Folder) {
        self.init(uid: folder.uid, name: folder.name, color: folder.colorRaw, symbol: folder.symbol,
                  parentID: folder.parentID, sortIndex: folder.sortIndex, createdAt: folder.createdAt)
    }

    func makeFolder() -> Folder {
        let folder = Folder(name: name, color: FolderColor(rawValue: color) ?? .blue,
                            symbol: FolderSymbol.all.contains(symbol) ? symbol : FolderSymbol.all[0],
                            parentID: parentID, sortIndex: sortIndex, createdAt: createdAt)
        folder.uid = uid
        return folder
    }
}
