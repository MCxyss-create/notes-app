import SwiftUI
import SwiftData

/// Изменение записи. Правки сохраняются сразу.
struct EditItemView: View {
    @Bindable var item: Item
    /// Демо-снимок: сразу открыть первое фото на весь экран.
    var demoViewer = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Folder.sortIndex) private var folders: [Folder]
    @Query private var photos: [PhotoAttachment]
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var viewer: PhotoViewerRequest?
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var confirmDelete = false
    @State private var deleted = false
    @State private var tagsText: String

    init(item: Item, demoViewer: Bool = false) {
        _item = Bindable(wrappedValue: item)
        self.demoViewer = demoViewer
        let id = item.uid
        _photos = Query(filter: #Predicate<PhotoAttachment> { $0.itemID == id }, sort: \.sortIndex)
        _tagsText = State(initialValue: item.tags.joined(separator: ", "))
        _hasDue = State(initialValue: item.dueAt != nil)
        _due = State(initialValue: item.dueAt
                     ?? DateMath.tomorrow(hour: AppDefaults.hour, minute: AppDefaults.minute, from: Date()))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Заголовок", text: $item.title, axis: .vertical)
                        .font(.headline)
                    TextField("Подробности", text: detailsBinding, axis: .vertical)
                        .lineLimit(3...10)
                }

                photoSection

                Section {
                    Picker("Вид", selection: kindBinding) {
                        ForEach(ItemKind.allCases) { k in
                            Label(k.title, systemImage: k.symbol).tag(k)
                        }
                    }
                }

                if item.kind == .reminder {
                    reminderSection
                } else {
                    folderSection
                }

                Section {
                    TextField("например: школа, сервер", text: $tagsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Теги")
                } footer: {
                    Text("Через запятую. В поиске — #тег.")
                }

                Section {
                    Toggle("Закрепить наверху", isOn: $item.isPinned)
                }

                if let raw = item.rawInput, !raw.isEmpty {
                    Section("Исходная фраза") {
                        Text(raw)
                            .foregroundStyle(Color.secondary)
                    }
                }

                Section {
                    Button("Удалить", role: .destructive) {
                        confirmDelete = true
                    }
                }
            }
            .keyboardDismissable()
            .navigationTitle(item.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .confirmationDialog("Удалить запись?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    deleteAfterClose()
                }
                Button("Отмена", role: .cancel) {}
            }
            .onChange(of: hasDue) { _, on in
                item.dueAt = on ? due : nil
                if on, item.remindBeforeMin == nil, AppDefaults.beforeMin > 0 {
                    item.remindBeforeMin = AppDefaults.beforeMin
                }
            }
            .onChange(of: due) { _, newValue in
                if hasDue, item.dueAt != newValue {
                    item.dueAt = newValue
                    item.timeGiven = true
                }
            }
            .onChange(of: tagsText) { _, value in
                item.tags = TagText.parse(value)
            }
            .photoPickers(library: $showLibrary, camera: $showCamera,
                          limit: PhotoMath.remaining(current: photos.count)) { added in
                PhotoStore.add(added, to: item.uid, context: context)
            }
            .fullScreenCover(item: $viewer) { request in
                PhotoViewer(itemID: item.uid, startIndex: request.index)
            }
            .task {
                guard demoViewer else { return }
                try? await Task.sleep(nanoseconds: 800_000_000)
                viewer = PhotoViewerRequest(index: 0)
            }
            .onDisappear {
                guard !deleted else { return }
                if item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    item.title = "Без названия"
                }
            }
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle("Напомнить", isOn: $hasDue)
            if hasDue {
                DatePicker("Когда", selection: $due)
                Picker("Заранее", selection: beforeBinding) {
                    ForEach(BeforeOption.all, id: \.minutes) { option in
                        Text(option.title).tag(option.minutes)
                    }
                }
                Picker("Повтор", selection: repeatBinding) {
                    Text("Не повторять").tag(RepeatRule?.none)
                    ForEach(RepeatRule.allCases, id: \.self) { rule in
                        Text(rule.title).tag(RepeatRule?.some(rule))
                    }
                }
            }
            Toggle("Выполнено", isOn: doneBinding)
        } header: {
            Text("Срок")
        } footer: {
            if item.repeatRule != nil {
                Text("Повторяется: «Выполнено» переносит дело на следующий раз.")
            }
        }
    }

    /// Фото к записи: сетка миниатюр (тап — на весь экран) и «Добавить фото», до 10 штук.
    private var photoSection: some View {
        Section {
            if !photos.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.element.uid) { offset, photo in
                        Button {
                            viewer = PhotoViewerRequest(index: offset)
                        } label: {
                            PhotoThumb(data: photo.thumbData, size: 72)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Фото \(offset + 1)")
                    }
                }
                .padding(.vertical, 4)
            }
            Menu {
                PhotoAddButtons(showLibrary: $showLibrary, showCamera: $showCamera)
            } label: {
                Label("Добавить фото", systemImage: "photo.badge.plus")
            }
            .disabled(photos.count >= PhotoMath.limit)
        } header: {
            HStack {
                Text("Фото")
                Spacer()
                Text(PhotoMath.counterText(photos.count))
            }
        }
    }

    /// У идей и заметок — папка. У дел строки нет: дела в папки не кладутся.
    private var folderSection: some View {
        Section {
            NavigationLink {
                FolderPickerList(selection: item.folderID) { picked in
                    item.folderID = picked
                }
                .navigationTitle("Папка")
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                LabeledContent("Папка", value: folderText)
            }
        }
    }

    private var folderText: String {
        let nodes = folders.map(\.node)
        guard let id = item.folderID, !FolderTree.isLoose(id, in: nodes) else { return "Без папки" }
        return FolderTree.pathText(id, in: nodes)
    }

    private var repeatBinding: Binding<RepeatRule?> {
        Binding(
            get: { item.repeatRule },
            set: { item.repeatRule = $0 }
        )
    }

    private var detailsBinding: Binding<String> {
        Binding(
            get: { item.body ?? "" },
            set: { item.body = $0.isEmpty ? nil : $0 }
        )
    }

    private var kindBinding: Binding<ItemKind> {
        Binding(
            get: { item.kind },
            set: { item.kind = $0 }
        )
    }

    private var beforeBinding: Binding<Int> {
        Binding(
            get: { item.remindBeforeMin ?? 0 },
            set: { item.remindBeforeMin = $0 == 0 ? nil : $0 }
        )
    }

    private var doneBinding: Binding<Bool> {
        Binding(
            get: { item.isDone },
            set: { newValue in
                if newValue {
                    // У повторяющегося дела срок переезжает на следующий раз.
                    ItemActions.complete(item)
                    if let next = item.dueAt { due = next }
                } else {
                    item.isDone = false
                    item.doneAt = nil
                }
            }
        )
    }

    /// Сначала закрываем экран, потом удаляем: так экран не обращается к удалённой записи.
    private func deleteAfterClose() {
        deleted = true
        let target = item
        let ctx = context
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            PhotoStore.deleteItem(target, context: ctx)
            try? ctx.save()
        }
    }
}
