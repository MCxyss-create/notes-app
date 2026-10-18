import SwiftUI
import SwiftData

/// Открыть папку: шаг пути в NavigationStack главного экрана.
struct FolderRoute: Hashable {
    let id: UUID
}

/// Экран папки: сверху вложенные папки, ниже идеи и заметки этой папки.
/// Поле ввода внизу кладёт новые записи сюда — RootView передаёт открытую папку в ComposerBar.
struct FolderView: View {
    let folderID: UUID
    var onEdit: (Item) -> Void

    @Query(sort: \Folder.sortIndex) private var folders: [Folder]
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]
    @State private var menu = FolderMenu()

    private var notes: [Item] {
        items.filter { $0.kind != .reminder }
    }

    /// Как в списках: закреплённые сверху, потом новые.
    private var entries: [Item] {
        notes
            .filter { $0.folderID == folderID }
            .sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned }
                return a.createdAt > b.createdAt
            }
    }

    var body: some View {
        Group {
            if let folder = folders.first(where: { $0.uid == folderID }) {
                List {
                    FolderSection(parentID: folderID, folders: folders, folderIDs: notes.map(\.folderID), menu: $menu)

                    Section {
                        let list = entries
                        if list.isEmpty {
                            Text("Пока пусто. Напиши внизу — запись ляжет в эту папку.")
                                .foregroundStyle(Color.secondary)
                        } else {
                            ForEach(list) { item in
                                NoteRow(item: item, onEdit: onEdit, onFile: { menu.filing = $0 })
                            }
                        }
                    } header: {
                        Text("Записи")
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle(folder.name)
            } else {
                ContentUnavailableView("Папки больше нет", systemImage: "folder",
                                       description: Text("Её удалили, записи переехали к родителю."))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissable()
        .folderSheets($menu)
    }
}

/// Что открыто поверх списка: форма папки, выбор места, вопрос об удалении.
struct FolderMenu {
    var editing: FolderEditRequest?
    var moving: Folder?
    var deleting: Folder?
    /// Идея или заметка, которую перекладывают «В папку…».
    var filing: Item?
}

/// Раздел «Папки»: папки одного уровня и «Новая папка». Долгое нажатие — меню папки.
struct FolderSection: View {
    let parentID: UUID?
    let folders: [Folder]
    /// Папки всех идей и заметок — для числа записей внутри.
    let folderIDs: [UUID?]
    @Binding var menu: FolderMenu

    var body: some View {
        let nodes = folders.map(\.node)
        let level = FolderTree.children(of: parentID, in: nodes)
        let canCreate = FolderTree.canCreate(in: parentID, nodes: nodes)
        if !level.isEmpty || canCreate {
            Section {
                ForEach(level) { node in
                    if let folder = folders.first(where: { $0.uid == node.id }) {
                        NavigationLink(value: FolderRoute(id: folder.uid)) {
                            FolderRow(folder: folder,
                                      count: FolderTree.count(in: folder.uid, folderIDs: folderIDs, nodes: nodes))
                        }
                        .contextMenu {
                            menuButtons(folder)
                        }
                    }
                }
                if canCreate {
                    Button {
                        menu.editing = .create(parent: parentID)
                    } label: {
                        Label("Новая папка", systemImage: "folder.badge.plus")
                    }
                }
            } header: {
                Text("Папки")
            }
        }
    }

    @ViewBuilder
    private func menuButtons(_ folder: Folder) -> some View {
        Button {
            menu.editing = .edit(folder)
        } label: {
            Label("Переименовать", systemImage: "pencil")
        }
        Button {
            menu.editing = .edit(folder)
        } label: {
            Label("Цвет и значок", systemImage: "paintpalette")
        }
        Button {
            menu.moving = folder
        } label: {
            Label("Переместить", systemImage: "folder")
        }
        Button(role: .destructive) {
            menu.deleting = folder
        } label: {
            Label("Удалить", systemImage: "trash")
        }
    }
}

/// Строка папки: значок, имя, сколько записей внутри вместе с вложенными.
struct FolderRow: View {
    let folder: Folder
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            FolderIcon(symbol: folder.symbol, color: folder.color)
            Text(folder.name)
                .lineLimit(1)
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)")
                    .foregroundStyle(Color.secondary)
            }
        }
    }
}

/// Значок папки: символ на цветном квадрате.
struct FolderIcon: View {
    let symbol: String
    let color: FolderColor
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(color.color, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }
}

extension FolderColor {
    var color: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .purple: return .purple
        case .pink: return .pink
        case .yellow: return .yellow
        case .gray: return .gray
        }
    }
}

/// Строка идеи или заметки: свайп вправо — закрепить, влево — удалить, меню — «В папку…».
struct NoteRow: View {
    let item: Item
    var onEdit: (Item) -> Void
    var onFile: (Item) -> Void

    @Environment(\.modelContext) private var context

    var body: some View {
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
                    onFile(item)
                } label: {
                    Label("В папку…", systemImage: "folder")
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

extension View {
    /// Форма папки, выбор места и вопрос об удалении — для экранов с разделом «Папки».
    func folderSheets(_ menu: Binding<FolderMenu>) -> some View {
        modifier(FolderSheets(menu: menu))
    }
}

private struct FolderSheets: ViewModifier {
    @Binding var menu: FolderMenu
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            .sheet(item: $menu.editing) { request in
                FolderEditView(request: request)
            }
            .sheet(item: $menu.moving) { folder in
                let nodes = FolderStore.all(context).map(\.node)
                FolderPickerSheet(title: "Переместить «\(folder.name)»", selection: folder.parentID,
                                  noneTitle: "Верхний уровень",
                                  isAllowed: { FolderTree.canMove(folder.uid, to: $0, in: nodes) }) { target in
                    FolderStore.move(folder, to: target, context: context)
                }
            }
            .sheet(item: $menu.filing) { item in
                FolderPickerSheet(title: "В папку", selection: item.folderID, noneTitle: "Без папки") { target in
                    FolderStore.file(item, into: target, context: context)
                }
            }
            .confirmationDialog(deleteTitle, isPresented: deleteShown, titleVisibility: .visible,
                                presenting: menu.deleting) { folder in
                Button("Удалить папку", role: .destructive) {
                    FolderStore.delete(folder, context: context)
                }
                Button("Отмена", role: .cancel) {}
            } message: { folder in
                Text(deleteMessage(folder))
            }
    }

    private var deleteTitle: String {
        menu.deleting.map { "Удалить папку «\($0.name)»?" } ?? ""
    }

    private var deleteShown: Binding<Bool> {
        Binding(
            get: { menu.deleting != nil },
            set: { if !$0 { menu.deleting = nil } }
        )
    }

    /// Записи никогда не удаляются молча: говорим, куда они переедут.
    private func deleteMessage(_ folder: Folder) -> String {
        if let parent = FolderStore.removalTargetName(folder, folders: FolderStore.all(context)) {
            return "Записи и вложенные папки переедут в «\(parent)»."
        }
        return "Записи переедут в «Без папки», вложенные папки — наверх."
    }
}
