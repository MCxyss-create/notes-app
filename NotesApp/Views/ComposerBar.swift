import SwiftUI
import SwiftData

/// Поле ввода внизу экрана: вид записи, срок, текст, кнопка «сохранить».
struct ComposerBar: View {
    let defaultKind: ItemKind
    let autoFocus: Bool
    var demoShowDue: Bool = false

    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKeys.defaultBeforeMin) private var defaultBefore = 15
    @State private var text = ""
    @State private var kind: ItemKind = .reminder
    @State private var due: Date?
    @State private var timeGiven = true
    @State private var showDue = false
    @State private var savedCount = 0
    @FocusState private var focused: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var placeholder: String {
        switch kind {
        case .reminder: return "Что напомнить?"
        case .idea: return "Запиши идею…"
        case .note: return "Запиши заметку…"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(ItemKind.allCases) { k in
                    kindChip(k)
                }
                Spacer(minLength: 4)
                if kind == .reminder {
                    dueChip
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                Button(action: save) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(trimmed.isEmpty ? Color.secondary : Color.accentColor)
                }
                .disabled(trimmed.isEmpty)
                .accessibilityLabel("Сохранить")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .sensoryFeedback(.success, trigger: savedCount)
        .onAppear {
            kind = defaultKind
            if demoShowDue {
                kind = .reminder
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showDue = true }
            } else if autoFocus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true }
            }
        }
        .onChange(of: defaultKind) { _, newKind in
            kind = newKind
        }
        .sheet(isPresented: $showDue) {
            DueDateSheet(selection: $due, timeGiven: $timeGiven)
        }
    }

    private func kindChip(_ k: ItemKind) -> some View {
        let selected = (k == kind)
        return Button {
            kind = k
        } label: {
            HStack(spacing: 4) {
                Image(systemName: k.symbol)
                if selected {
                    Text(k.title)
                }
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(k.title)
    }

    private var dueChip: some View {
        Button {
            showDue = true
        } label: {
            Label(due.map { DateText.short($0) } ?? "Без срока", systemImage: "clock")
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(due == nil ? Color.secondary : Color.accentColor)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Когда напомнить")
    }

    private func save() {
        let value = trimmed
        guard !value.isEmpty else { return }

        // Первая строка — заголовок, остальное — подробности.
        let parts = value.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
        let title = String(parts.first ?? Substring(value)).trimmingCharacters(in: .whitespaces)
        let rest = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""

        let isReminder = kind == .reminder
        let dueDate = isReminder ? due : nil
        let item = Item(
            kind: kind,
            title: title,
            body: rest.isEmpty ? nil : rest,
            dueAt: dueDate,
            timeGiven: timeGiven,
            remindBeforeMin: (dueDate != nil && defaultBefore > 0) ? defaultBefore : nil
        )
        withAnimation {
            context.insert(item)
        }
        try? context.save()

        text = ""
        due = nil
        timeGiven = true
        savedCount += 1
    }
}
