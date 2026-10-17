import SwiftUI
import SwiftData

/// Поиск по всем записям. Пустой запрос — список тегов.
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]
    @State private var query: String
    @State private var editing: Item?

    init(initialQuery: String = "") {
        _query = State(initialValue: initialQuery)
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
        let found = items.filter { SearchMatcher.matches(SearchFields(item: $0), query: query) }
        if found.isEmpty {
            Section {
                Text("Ничего не нашлось")
                    .foregroundStyle(Color.secondary)
            }
        } else {
            ForEach(ItemKind.allCases) { kind in
                let group = found.filter { $0.kind == kind }
                if !group.isEmpty {
                    Section(sectionTitle(kind, count: group.count)) {
                        ForEach(group) { item in
                            ItemRow(item: item, now: Date())
                                .contentShape(Rectangle())
                                .onTapGesture { editing = item }
                        }
                    }
                }
            }
        }
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
    init(item: Item) {
        self.init(title: item.title, body: item.body, rawInput: item.rawInput, tags: item.tags)
    }
}
