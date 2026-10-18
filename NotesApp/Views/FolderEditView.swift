import SwiftUI
import SwiftData

/// Что открыть в форме папки: новую (внутри parent) или существующую.
enum FolderEditRequest: Identifiable {
    case create(parent: UUID?)
    case edit(Folder)

    var id: String {
        switch self {
        case .create(let parent): return "new-\(parent?.uuidString ?? "top")"
        case .edit(let folder): return folder.uid.uuidString
        }
    }
}

/// Форма папки: название, цвет, значок, «Внутри папки».
struct FolderEditView: View {
    let request: FolderEditRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Folder.sortIndex) private var folders: [Folder]
    @State private var name: String
    @State private var color: FolderColor
    @State private var symbol: String
    @State private var parentID: UUID?

    init(request: FolderEditRequest) {
        self.request = request
        switch request {
        case .create(let parent):
            _name = State(initialValue: "")
            _color = State(initialValue: .blue)
            _symbol = State(initialValue: FolderSymbol.all[0])
            _parentID = State(initialValue: parent)
        case .edit(let folder):
            _name = State(initialValue: folder.name)
            _color = State(initialValue: folder.color)
            _symbol = State(initialValue: folder.symbol)
            _parentID = State(initialValue: folder.parentID)
        }
    }

    private var editing: Folder? {
        if case .edit(let folder) = request { return folder }
        return nil
    }

    private var nodes: [FolderNode] {
        folders.map(\.node)
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Куда можно положить эту папку.
    private func allowed(_ parent: UUID?) -> Bool {
        if let editing {
            return FolderTree.canMove(editing.uid, to: parent, in: nodes)
        }
        return FolderTree.canCreate(in: parent, nodes: nodes)
    }

    private var problem: String? {
        if !trimmed.isEmpty, FolderTree.isNameTaken(trimmed, in: parentID, excluding: editing?.uid, nodes: nodes) {
            return "Папка «\(trimmed)» здесь уже есть"
        }
        if !allowed(parentID) {
            return "Сюда нельзя: не больше \(FolderTree.maxDepth) уровней, и не внутрь самой себя"
        }
        return nil
    }

    private var parentText: String {
        guard let parentID, !FolderTree.isLoose(parentID, in: nodes) else { return "Верхний уровень" }
        return FolderTree.pathText(parentID, in: nodes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        FolderIcon(symbol: symbol, color: color, size: 36)
                        TextField("Название", text: $name)
                            .font(.headline)
                    }
                }

                Section("Цвет") {
                    HStack(spacing: 0) {
                        ForEach(FolderColor.allCases) { option in
                            Button {
                                color = option
                            } label: {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if option == color {
                                            Circle()
                                                .strokeBorder(Color.primary, lineWidth: 3)
                                                .frame(width: 36, height: 36)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.title)
                        }
                    }
                }

                Section("Значок") {
                    HStack(spacing: 0) {
                        ForEach(FolderSymbol.all, id: \.self) { option in
                            Button {
                                symbol = option
                            } label: {
                                Image(systemName: option)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(option == symbol ? Color.white : Color.primary)
                                    .frame(width: 34, height: 34)
                                    .background(option == symbol ? color.color : Color(.tertiarySystemFill),
                                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        FolderPickerList(selection: parentID, noneTitle: "Верхний уровень",
                                         isAllowed: { allowed($0) }) { picked in
                            parentID = picked
                        }
                        .navigationTitle("Внутри папки")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        LabeledContent("Внутри папки", value: parentText)
                    }
                } footer: {
                    if let problem {
                        Text(problem)
                            .foregroundStyle(Color.red)
                    } else {
                        Text("Папки вкладываются до \(FolderTree.maxDepth) уровней: Проекты → VPN → Реклама.")
                    }
                }
            }
            .keyboardDismissable()
            .navigationTitle(editing == nil ? "Новая папка" : "Папка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Создать" : "Готово") {
                        save()
                    }
                    .disabled(trimmed.isEmpty || problem != nil)
                }
            }
        }
    }

    private func save() {
        if let editing {
            editing.name = trimmed
            editing.color = color
            editing.symbol = symbol
            if editing.parentID != parentID {
                FolderStore.move(editing, to: parentID, context: context)
            }
            try? context.save()
        } else {
            FolderStore.create(name: trimmed, color: color, symbol: symbol, parentID: parentID, context: context)
        }
        dismiss()
    }
}

/// Выбор папки деревом, с отступами. noneTitle — «Без папки» или «Верхний уровень».
struct FolderPickerList: View {
    let selection: UUID?
    var noneTitle = "Без папки"
    /// Куда класть нельзя (для папки — в себя, в подпапку, слишком глубоко) — серым.
    var isAllowed: (UUID?) -> Bool = { _ in true }
    let onPick: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Folder.sortIndex) private var folders: [Folder]

    var body: some View {
        let nodes = folders.map(\.node)
        let current = FolderTree.isLoose(selection, in: nodes) ? nil : selection
        List {
            option(nil, title: noneTitle, icon: Image(systemName: "tray"), level: 0, selected: current == nil)
            ForEach(FolderTree.lines(nodes)) { line in
                if let folder = folders.first(where: { $0.uid == line.id }) {
                    option(folder.uid, title: folder.name,
                           icon: FolderIcon(symbol: folder.symbol, color: folder.color, size: 26),
                           level: line.level, selected: current == folder.uid)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func option(_ id: UUID?, title: String, icon: some View, level: Int, selected: Bool) -> some View {
        let enabled = isAllowed(id)
        return Button {
            onPick(id)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                icon
                    .foregroundStyle(Color.secondary)
                    .frame(width: 26)
                Text(title)
                    .foregroundStyle(enabled ? Color.primary : Color.secondary)
                Spacer(minLength: 4)
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.leading, CGFloat(level) * 24)
        }
        .disabled(!enabled)
    }
}

/// Выбор папки листом поверх: «В папку…» у записи и «Переместить» у папки.
struct FolderPickerSheet: View {
    let title: String
    let selection: UUID?
    var noneTitle = "Без папки"
    var isAllowed: (UUID?) -> Bool = { _ in true }
    let onPick: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FolderPickerList(selection: selection, noneTitle: noneTitle, isAllowed: isAllowed, onPick: onPick)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }
                    }
                }
        }
    }
}
