import SwiftUI
import SwiftData

/// Запрос на открытие поиска (пустой — просто открыть).
struct SearchRequest: Identifiable {
    let id = UUID()
    let query: String
}

/// Поиск по всем записям. Пустой запрос — список тегов.
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]
    @Query(sort: \Folder.sortIndex) private var folders: [Folder]
    @Query(sort: \CalendarEvent.createdAt) private var events: [CalendarEvent]
    @State private var query = ""
    @State private var editing: Item?
    @State private var editingEvent: EventEditRequest?
    private let initialQuery: String

    init(initialQuery: String = "") {
        self.initialQuery = initialQuery
    }

    private struct TagCount: Hashable {
        let tag: String
        let count: Int
    }

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    tagsSection
                } else {
                    results
                }
            }
            .listStyle(.insetGrouped)
            .keyboardDismissable()
            .navigationTitle("Поиск")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Слово или #тег")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .sheet(item: $editing) { item in
                EditItemView(item: item)
            }
            .sheet(item: $editingEvent) { request in
                NavigationStack {
                    EventEditView(request: request)
                }
            }
            .task {
                // Поле поиска при появлении обнуляет текст, поэтому начальный запрос — чуть позже.
                guard !initialQuery.isEmpty else { return }
                try? await Task.sleep(nanoseconds: 400_000_000)
                query = initialQuery
            }
        }
    }

    private var tagCounts: [TagCount] {
        var counts: [String: Int] = [:]
        for item in items {
            for tag in item.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .map { TagCount(tag: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
    }

    @ViewBuilder
    private var tagsSection: some View {
        let tags = tagCounts
        if tags.isEmpty {
            Section {
                Text("Ищи по словам. Теги появятся здесь, когда добавишь их к записям.")
                    .foregroundStyle(Color.secondary)
            }
        } else {
            Section("Теги") {
                ForEach(tags, id: \.tag) { entry in
                    Button {
                        query = "#\(entry.tag)"
                    } label: {
                        HStack {
                            Text("#\(entry.tag)")
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                            Text("\(entry.count)")
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        let nodes = folders.map(\.node)
        let found = items.filter {
            SearchMatcher.matches(SearchFields(item: $0, folderPath: folderPath($0, nodes: nodes)), query: query)
        }
        // События календаря — по имени и заметке.
        let foundEvents = events.filter {
            SearchMatcher.matches(SearchFields(title: $0.title, body: $0.note, rawInput: nil, tags: []), query: query)
        }
        if !foundEvents.isEmpty {
            Section("Календарь · \(foundEvents.count)") {
                ForEach(foundEvents) { event in
                    HStack(spacing: 12) {
                        Image(systemName: event.type.symbol)
                            .foregroundStyle(event.type.color)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                            Text("\(event.type.title) · \(CalendarMath.dayMonthText(month: event.month, day: event.day))")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editingEvent = .edit(event) }
                }
            }
        }
        if found.isEmpty && foundEvents.isEmpty {
            Section {
                Text("Ничего не нашлось")
                    .foregroundStyle(Color.secondary)
            }
        } else if !found.isEmpty {
            ForEach(ItemKind.allCases) { kind in
                let group = found.filter { $0.kind == kind }
                if !group.isEmpty {
                    Section(sectionTitle(kind, count: group.count)) {
                        ForEach(group) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                ItemRow(item: item, now: Date())
                                if let path = folderPath(item, nodes: nodes) {
                                    Label(path, systemImage: "folder")
                                        .font(.caption)
                                        .foregroundStyle(Color.secondary)
                                        .padding(.leading, 36)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { editing = item }
                        }
                    }
                }
            }
        }
    }

    /// Путь папки записи серым под строкой. Без папки — nil.
    private func folderPath(_ item: Item, nodes: [FolderNode]) -> String? {
        guard let id = item.folderID, !FolderTree.isLoose(id, in: nodes) else { return nil }
        return FolderTree.pathText(id, in: nodes)
    }

    private func sectionTitle(_ kind: ItemKind, count: Int) -> String {
        switch kind {
        case .reminder: return "Напоминания · \(count)"
        case .idea: return "Идеи · \(count)"
        case .note: return "Заметки · \(count)"
        }
    }
}

extension SearchFields {
    init(item: Item, folderPath: String? = nil) {
        self.init(title: item.title, body: item.body, rawInput: item.rawInput, tags: item.tags, folderPath: folderPath)
    }
}
