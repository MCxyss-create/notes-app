import SwiftUI
import SwiftData

/// Список идей или заметок. Закреплённые — сверху.
struct ItemListView: View {
    let kind: ItemKind
    var onEdit: (Item) -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]

    private var visible: [Item] {
        items
            .filter { $0.kind == kind }
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
        if list.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: kind.symbol, description: Text(emptyText))
        } else {
            List {
                ForEach(list) { item in
                    row(item)
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func row(_ item: Item) -> some View {
        ItemRow(item: item, now: Date())
            .contentShape(Rectangle())
            .onTapGesture { onEdit(item) }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    withAnimation { item.isPinned.toggle() }
                } label: {
                    Label(item.isPinned ? "Открепить" : "Закрепить",
                          systemImage: item.isPinned ? "pin.slash" : "pin")
                }
                .tint(.orange)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    withAnimation { context.delete(item) }
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
            .contextMenu {
                Button {
                    onEdit(item)
                } label: {
                    Label("Изменить", systemImage: "pencil")
                }
                Button {
                    withAnimation { item.isPinned.toggle() }
                } label: {
                    Label(item.isPinned ? "Открепить" : "Закрепить", systemImage: "pin")
                }
                Button(role: .destructive) {
                    withAnimation { context.delete(item) }
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
    }
}
