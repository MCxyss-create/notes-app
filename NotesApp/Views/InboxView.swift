import SwiftUI
import SwiftData

/// «Входящие»: фразы, которые ИИ не разобрал сразу. Разобранные открываются карточками.
struct InboxView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \InboxEntry.createdAt) private var entries: [InboxEntry]
    @State private var review: AIReview?
    @State private var reviewEntry: UUID?
    @State private var working = false
    @State private var hasKey = AISettings.hasKey
    @State private var message: String?

    private var waitingCount: Int {
        entries.filter { $0.parsedJSON == nil }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "Входящих нет",
                        systemImage: "tray",
                        description: Text("Сюда попадают фразы, которые ИИ не смог разобрать сразу: не было сети или ключа.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(entries) { entry in
                                row(entry)
                            }
                        } footer: {
                            Text("Разбираются сами, когда есть сеть и ключ DeepSeek. Разобранную фразу открой и сохрани.")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Входящие")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if waitingCount > 0 {
                    parseAllBar
                }
            }
            .sheet(item: $review) { r in
                AIReviewView(review: r) { drafts, changes in
                    AIService.save(drafts, phrase: r.phrase, context: context)
                    AIService.apply(changes, context: context)
                    if let id = reviewEntry, let entry = entries.first(where: { $0.uid == id }) {
                        context.delete(entry)
                        try? context.save()
                    }
                }
            }
        }
    }

    private var parseAllBar: some View {
        VStack(spacing: 6) {
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.orange)
            }
            Button {
                Task { await parseAll() }
            } label: {
                HStack {
                    if working {
                        ProgressView()
                    }
                    Text(working ? "Разбираю…" : "Разобрать сейчас (\(waitingCount))")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(working)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func row(_ entry: InboxEntry) -> some View {
        Button {
            open(entry)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .foregroundStyle(Color.primary)
                    .lineLimit(3)
                HStack(spacing: 4) {
                    Text(DateText.short(entry.createdAt))
                        .foregroundStyle(Color.secondary)
                    Text("·")
                        .foregroundStyle(Color.secondary)
                    status(entry)
                }
                .font(.caption)
            }
            .padding(.vertical, 2)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                delete(entry)
            } label: {
                Label("Удалить", systemImage: "trash")
            }
            Button {
                saveAsNote(entry)
            } label: {
                Label("Заметкой", systemImage: "note.text")
            }
            .tint(.gray)
        }
    }

    @ViewBuilder
    private func status(_ entry: InboxEntry) -> some View {
        if entry.parsedJSON != nil {
            Text("Разобрано — открой")
                .foregroundStyle(Color.green)
        } else if let error = entry.lastError {
            Text(error)
                .foregroundStyle(Color.orange)
        } else if !hasKey {
            Text("Нужен ключ DeepSeek")
                .foregroundStyle(Color.orange)
        } else {
            Text("Ждёт сети")
                .foregroundStyle(Color.secondary)
        }
    }

    private func open(_ entry: InboxEntry) {
        let known = AIService.knownItems(context)
        guard let json = entry.parsedJSON,
              let result = try? AIService.parse(json, said: entry.createdAt, known: known,
                                                folders: AIService.knownFolders(context)) else {
            Task { await parseAll() }
            return
        }
        reviewEntry = entry.uid
        review = AIReview(phrase: entry.text, reply: result.reply, drafts: result.drafts,
                          changes: result.changes, found: result.found, answered: result.answered)
    }

    private func parseAll() async {
        hasKey = AISettings.hasKey
        guard hasKey else {
            message = AIError.noKey.message
            return
        }
        message = nil
        working = true
        await InboxProcessor.shared.run(retryFailed: true)
        working = false
        if let stuck = entries.first(where: { $0.parsedJSON == nil && $0.lastError == nil }) {
            message = "«\(stuck.text.prefix(30))…» ещё ждёт: нет сети или DeepSeek не ответил"
        }
    }

    private func saveAsNote(_ entry: InboxEntry) {
        AIService.save([AIDraft.note(from: entry.text)], phrase: entry.text, source: .manual, context: context)
        delete(entry)
    }

    private func delete(_ entry: InboxEntry) {
        withAnimation {
            context.delete(entry)
        }
        try? context.save()
    }
}
