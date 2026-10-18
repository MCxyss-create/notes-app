import Foundation
import SwiftData

/// Изменения папок в базе. Удаление никогда не теряет записи: всё переезжает к родителю.
@MainActor
enum FolderStore {
    static func all(_ context: ModelContext) -> [Folder] {
        (try? context.fetch(FetchDescriptor<Folder>())) ?? []
    }

    /// Новая папка — в конец списка.
    @discardableResult
    static func create(name: String, color: FolderColor, symbol: String, parentID: UUID?,
                       context: ModelContext) -> Folder {
        let next = (all(context).map(\.sortIndex).max() ?? -1) + 1
        let folder = Folder(name: name.trimmingCharacters(in: .whitespacesAndNewlines), color: color,
                            symbol: symbol, parentID: parentID, sortIndex: next)
        context.insert(folder)
        try? context.save()
        return folder
    }

    /// Куда переедет содержимое при удалении: имя родителя или «Без папки».
    static func removalTargetName(_ folder: Folder, folders: [Folder]) -> String? {
        let nodes = folders.map(\.node)
        guard let target = FolderTree.removal(of: folder.uid, in: nodes).target else { return nil }
        return folders.first { $0.uid == target }?.name
    }

    /// Удаляет папку: записи — к родителю (наверху — «Без папки»), подпапки — к родителю.
    static func delete(_ folder: Folder, context: ModelContext) {
        let folders = all(context)
        let removal = FolderTree.removal(of: folder.uid, in: folders.map(\.node))
        let id = folder.uid
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        for item in items where item.folderID == id {
            item.folderID = removal.target
        }
        for child in folders {
            guard let name = removal.renamed[child.uid] else { continue }
            child.parentID = removal.target
            child.name = name
        }
        context.delete(folder)
        try? context.save()
    }

    /// Переложить папку. Нельзя в себя, в подпапку и глубже 3 уровней — тогда ничего не меняется.
    static func move(_ folder: Folder, to parentID: UUID?, context: ModelContext) {
        let folders = all(context)
        let nodes = folders.map(\.node)
        guard FolderTree.canMove(folder.uid, to: parentID, in: nodes) else { return }
        folder.name = FolderTree.uniqueName(folder.name, in: parentID, excluding: folder.uid, nodes: nodes)
        folder.parentID = parentID
        try? context.save()
    }

    /// Переложить идею или заметку. Дела в папки не кладутся.
    static func file(_ item: Item, into folderID: UUID?, context: ModelContext) {
        guard item.kind != .reminder else { return }
        item.folderID = folderID
        try? context.save()
    }
}
