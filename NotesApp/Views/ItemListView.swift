import SwiftUI
import SwiftData

/// Список идей или заметок. Сверху — папки, ниже — записи без папки, закреплённые сверху.
/// Записи из папок сюда не попадают — они внутри папок (поиск находит всё).
struct ItemListView: View {
    let kind: ItemKind
    var onEdit: (Item) -> Void

    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]
    @Query(sort: \Folder.sortIndex) private var folders: [Folder]
    @State private var menu = FolderMenu()

    private var visible: [Item] {
        let nodes = folders.map(\.node)
        return items
            .filter { $0.kind == kind && FolderTree.isLoose($0.folderID, in: nodes) }
            .sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned }
                return a.createdAt > b.createdAt
            }
    }

    private var emptyTitle: String {
        kind == .idea ? "Идей пока нет" : "Заметок пока нет"
    }

    private var emptyText: String {
        kind == .idea ? "Напиши идею внизу — она появится здесь." : "Напиши заметку внизу — она появится здесь."
    }

    var body: some View {
        let list = visible
        Group {
            if list.isEmpty && folders.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: kind.symbol)
                } description: {
                    Text(emptyText)
                } actions: {
                    Button("Новая папка") {
                        menu.editing = .create(parent: nil)
                    }
                }
            } else {
                List {
                    FolderSection(parentID: nil, folders: folders,
                                  folderIDs: items.filter { $0.kind != .reminder }.map(\.folderID), menu: $menu)

                    Section {
                        if list.isEmpty {
                            Text(emptyText)
                                .foregroundStyle(Color.secondary)
                        } else {
                            ForEach(list) { item in
                                NoteRow(item: item, onEdit: onEdit, onFile: { menu.filing = $0 })
                            }
                        }
                    } header: {
                        if !folders.isEmpty {
                            Text("Без папки")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .folderSheets($menu)
    }
}
