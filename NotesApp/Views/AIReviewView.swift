import SwiftUI

/// Что ИИ понял из одной фразы.
struct AIReview: Identifiable {
    let id = UUID()
    let phrase: String
    let reply: String
    var drafts: [AIDraft]
    var changes: [AIChange] = []
    var found: [AIKnownItem] = []
    var answered = false
}

/// «Вот что я понял»: карточки перед сохранением. Несколько дел — несколько карточек, одна кнопка.
/// Команды («перенеси», «готово», «удали») — тоже карточками: применяются только по кнопке.
struct AIReviewView: View {
    let onSave: ([AIDraft], [AIChange]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var review: AIReview

    init(review: AIReview, onSave: @escaping ([AIDraft], [AIChange]) -> Void) {
        _review = State(initialValue: review)
        self.onSave = onSave
    }

    private var chosen: [AIDraft] {
        review.drafts.filter(\.include)
    }

    private var chosenChanges: [AIChange] {
        review.changes.filter(\.include)
    }

    private var hasActions: Bool {
        !review.drafts.isEmpty || !review.changes.isEmpty
    }

    /// Галочки «сохранить / не сохранять» нужны, только когда карточек больше одной.
    private var selectable: Bool {
        review.drafts.count + review.changes.count > 1
    }

    private var saveTitle: String {
        let total = chosen.count + chosenChanges.count
        if chosen.isEmpty && !chosenChanges.isEmpty {
            return total > 1 ? "Применить (\(total))" : "Применить"
        }
        return total > 1 ? "Сохранить все (\(total))" : "Сохранить"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        if !review.reply.isEmpty {
                            Label(review.reply, systemImage: "sparkles")
                                .font(.headline)
                        }
                        Text("«\(review.phrase)»")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                    .padding(.vertical, 2)
                }

                if !review.found.isEmpty {
                    Section("Нашёл") {
                        ForEach(review.found) { item in
                            FoundRow(item: item)
                        }
                    }
                }

                if !review.changes.isEmpty {
                    Section("Изменить") {
                        ForEach($review.changes) { $change in
                            ChangeRow(change: change, selectable: selectable) {
                                change.include.toggle()
                            }
                        }
                    }
                }

                if review.drafts.isEmpty {
                    if review.changes.isEmpty && !review.answered {
                        Section {
                            Text("Не понял, что тут записать.")
                            Button("Сохранить как заметку") {
                                finish([AIDraft.note(from: review.phrase)], [])
                            }
                        }
                    }
                } else {
                    ForEach($review.drafts) { $draft in
                        Section {
                            DraftCard(draft: draft, selectable: selectable) {
                                draft.include.toggle()
                            }
                            NavigationLink {
                                DraftEditView(draft: $draft)
                            } label: {
                                Label("Изменить", systemImage: "pencil")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Вот что я понял")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if hasActions || review.answered {
                    Button {
                        finish(chosen, chosenChanges)
                    } label: {
                        Text(hasActions ? saveTitle : "Понятно")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(hasActions && chosen.isEmpty && chosenChanges.isEmpty)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
            }
        }
    }

    private func finish(_ drafts: [AIDraft], _ changes: [AIChange]) {
        onSave(drafts, changes)
        dismiss()
    }
}

/// Карточка команды: что сделать с какой записью. Удаление — красным.
struct ChangeRow: View {
    let change: AIChange
    let selectable: Bool
    var onToggle: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if selectable {
                Button(action: onToggle) {
                    Image(systemName: change.include ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(change.include ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(change.include ? "Не применять" : "Применить")
            }

            VStack(alignment: .leading, spacing: 4) {
                Label(change.op.title, systemImage: change.op.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(change.op == .delete ? Color.red : Color.accentColor)
                Text(change.target.title)
                    .font(.headline)
                    .strikethrough(change.op == .delete)

                switch change.op {
                case .move:
                    if let due = change.due {
                        Label("\(change.target.due.map { DateText.short($0) } ?? "Без срока") → \(DateText.short(due))",
                              systemImage: "clock")
                            .font(.subheadline)
                    }
                case .edit:
                    if let title = change.title {
                        Text("→ \(title)")
                            .font(.subheadline)
                    }
                    if let details = change.body {
                        Text(details)
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                case .done:
                    if change.target.repeatRule != nil {
                        Text("Повторяется — перейдёт на следующий раз")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                case .delete:
                    EmptyView()
                }

                if let warning = change.warning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .opacity(change.include ? 1 : 0.45)
    }
}

/// Запись из ответа на вопрос: вид, заголовок, срок (просроченный — красным).
struct FoundRow: View {
    let item: AIKnownItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.kind.symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                if let due = item.due {
                    Text(dueText(due))
                        .font(.caption)
                        .foregroundStyle(due < Date() ? Color.red : Color.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func dueText(_ due: Date) -> String {
        guard let rule = item.repeatRule else { return DateText.short(due) }
        return "\(DateText.short(due)) · \(rule.title.lowercased())"
    }
}

/// Карточка одной записи: вид, заголовок, срок, «заранее», повтор, теги, предупреждение.
struct DraftCard: View {
    let draft: AIDraft
    let selectable: Bool
    var onToggle: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if selectable {
                Button(action: onToggle) {
                    Image(systemName: draft.include ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(draft.include ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(draft.include ? "Не сохранять" : "Сохранить")
            }

            VStack(alignment: .leading, spacing: 4) {
                Label(draft.kind.title, systemImage: draft.kind.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(draft.title)
                    .font(.headline)
                if let details = draft.body {
                    Text(details)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }

                if draft.kind == .reminder {
                    Group {
                        if let due = draft.due {
                            Label(DateText.short(due), systemImage: "clock")
                            if let before = draft.remindBeforeMin {
                                Label(beforeText(before), systemImage: "bell")
                            }
                            if let rule = draft.repeatRule {
                                Label(rule.title, systemImage: "repeat")
                            }
                        } else {
                            Label("Без срока", systemImage: "clock")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
                }

                if !draft.tags.isEmpty {
                    Text(draft.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }

                if let warning = draft.warning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .opacity(draft.include ? 1 : 0.45)
    }

    private func beforeText(_ minutes: Int) -> String {
        BeforeOption.all.first { $0.minutes == minutes }?.title ?? "За \(minutes) мин"
    }
}

/// Правка карточки до сохранения.
struct DraftEditView: View {
    @Binding var draft: AIDraft
    @State private var tagsText = ""

    var body: some View {
        Form {
            Section {
                TextField("Заголовок", text: $draft.title, axis: .vertical)
                    .font(.headline)
                TextField("Подробности", text: detailsBinding, axis: .vertical)
                    .lineLimit(2...6)
            }

            Section {
                Picker("Вид", selection: $draft.kind) {
                    ForEach(ItemKind.allCases) { k in
                        Label(k.title, systemImage: k.symbol).tag(k)
                    }
                }
            }

            if draft.kind == .reminder {
                Section("Срок") {
                    Toggle("Напомнить", isOn: hasDueBinding)
                    if draft.due != nil {
                        DatePicker("Когда", selection: dueBinding)
                        Picker("Заранее", selection: beforeBinding) {
                            ForEach(BeforeOption.all, id: \.minutes) { option in
                                Text(option.title).tag(option.minutes)
                            }
                        }
                        Picker("Повтор", selection: $draft.repeatRule) {
                            Text("Не повторять").tag(RepeatRule?.none)
                            ForEach(RepeatRule.allCases, id: \.self) { rule in
                                Text(rule.title).tag(RepeatRule?.some(rule))
                            }
                        }
                    }
                }
            }

            Section("Теги") {
                TextField("через запятую", text: $tagsText)
                    .textInputAutocapitalization(.never)
            }
        }
        .navigationTitle("Изменить")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            tagsText = draft.tags.joined(separator: ", ")
        }
        .onChange(of: tagsText) { _, value in
            draft.tags = AIParser.tags(value)
        }
    }

    private var detailsBinding: Binding<String> {
        Binding(
            get: { draft.body ?? "" },
            set: { draft.body = $0.isEmpty ? nil : $0 }
        )
    }

    private var hasDueBinding: Binding<Bool> {
        Binding(
            get: { draft.due != nil },
            set: { on in
                if on {
                    draft.due = DateMath.tomorrow(hour: AppDefaults.hour, minute: AppDefaults.minute, from: Date())
                    draft.timeGiven = false
                    if draft.remindBeforeMin == nil, AppDefaults.beforeMin > 0 {
                        draft.remindBeforeMin = AppDefaults.beforeMin
                    }
                } else {
                    draft.due = nil
                }
                draft.warning = nil
            }
        )
    }

    private var dueBinding: Binding<Date> {
        Binding(
            get: { draft.due ?? Date() },
            set: { newValue in
                draft.due = newValue
                draft.timeGiven = true
                draft.warning = nil
            }
        )
    }

    private var beforeBinding: Binding<Int> {
        Binding(
            get: { draft.remindBeforeMin ?? 0 },
            set: { draft.remindBeforeMin = $0 == 0 ? nil : $0 }
        )
    }
}
