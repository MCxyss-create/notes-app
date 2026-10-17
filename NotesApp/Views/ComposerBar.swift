import SwiftUI
import SwiftData

/// Поле ввода внизу экрана. С ✨ фразу разбирает ИИ и показывает карточки «вот что я понял»;
/// без ✨ — вид записи, срок, текст, кнопка «сохранить».
struct ComposerBar: View {
    let defaultKind: ItemKind
    let autoFocus: Bool
    var demoShowDue: Bool = false
    var demoReview: AIReview? = nil

    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKeys.defaultBeforeMin) private var defaultBefore = 15
    @AppStorage(SettingsKeys.aiEnabled) private var aiOn = true
    @State private var text = ""
    @State private var kind: ItemKind = .reminder
    @State private var due: Date?
    @State private var timeGiven = true
    @State private var showDue = false
    @State private var savedCount = 0
    @State private var working = false
    @State private var notice: String?
    @State private var review: AIReview?
    @State private var reviewPhrase: String?
    @State private var reviewSaved = false
    @State private var textBeforeDictation = ""
    @StateObject private var dictation = Dictation()
    @ObservedObject private var launch = QuickLaunch.shared
    @FocusState private var focused: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var placeholder: String {
        if aiOn { return "Напиши или надиктуй…" }
        switch kind {
        case .reminder: return "Что напомнить?"
        case .idea: return "Запиши идею…"
        case .note: return "Запиши заметку…"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if aiOn {
                aiStatus
            } else {
                HStack(spacing: 6) {
                    ForEach(ItemKind.allCases) { k in
                        kindChip(k)
                    }
                    Spacer(minLength: 4)
                    if kind == .reminder {
                        dueChip
                    }
                }
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Color.orange)
                        .lineLimit(2)
                        .padding(.horizontal, 4)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                aiButton

                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                if dictation.isRecording {
                    Button {
                        dictation.stop()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Color.red)
                    }
                    .accessibilityLabel("Остановить запись")
                } else if working {
                    ProgressView()
                        .frame(width: 34, height: 40)
                } else if trimmed.isEmpty {
                    Button(action: startDictation) {
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Color.accentColor)
                    }
                    .accessibilityLabel("Надиктовать")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(trimmed.isEmpty ? Color.secondary : Color.accentColor)
                    }
                    .disabled(trimmed.isEmpty)
                    .accessibilityLabel(aiOn ? "Разобрать" : "Сохранить")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .sensoryFeedback(.success, trigger: savedCount)
        .onAppear {
            kind = defaultKind
            if let demoReview {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { review = demoReview }
            } else if demoShowDue {
                kind = .reminder
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showDue = true }
            } else if autoFocus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true }
            }
            handleLaunch()
        }
        .onChange(of: launch.pending) {
            handleLaunch()
        }
        .onChange(of: defaultKind) { _, newKind in
            kind = newKind
        }
        .onChange(of: dictation.transcript) { _, spoken in
            guard !spoken.isEmpty else { return }
            text = textBeforeDictation.isEmpty ? spoken : "\(textBeforeDictation) \(spoken)"
        }
        .onChange(of: dictation.error) { _, problem in
            guard let problem else { return }
            notice = problem
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                if notice == problem { notice = nil }
            }
        }
        .sheet(isPresented: $showDue) {
            DueDateSheet(selection: $due, timeGiven: $timeGiven)
        }
        .sheet(item: $review, onDismiss: reviewClosed) { r in
            AIReviewView(review: r) { drafts in
                AIService.save(drafts, phrase: r.phrase, context: context)
                reviewSaved = true
                savedCount += 1
            }
        }
    }

    /// Строка над полем, когда включён ИИ: подсказка, «разбираю…» или что пошло не так.
    private var aiStatus: some View {
        HStack(spacing: 6) {
            if working {
                ProgressView()
                    .controlSize(.small)
                Text("Разбираю…")
            } else if let notice {
                Image(systemName: "tray.and.arrow.down")
                Text(notice)
                    .foregroundStyle(Color.orange)
            } else {
                Image(systemName: "sparkles")
                Text("ИИ сам поймёт: дело, идея или заметка")
            }
        }
        .font(.footnote)
        .foregroundStyle(Color.secondary)
        .lineLimit(2)
        .padding(.horizontal, 4)
    }

    private var aiButton: some View {
        Button {
            aiOn.toggle()
            notice = nil
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(aiOn ? Color.white : Color.secondary)
                .background(aiOn ? Color.accentColor : Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 3)
        .accessibilityLabel(aiOn ? "Разбор через ИИ включён" : "Разбор через ИИ выключен")
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

    /// Приложение открыла команда: «Надиктовать» — сразу микрофон, иначе — клавиатура.
    private func handleLaunch() {
        guard let action = launch.take() else { return }
        switch action {
        case .dictate:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { startDictation() }
        case .type:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true }
        }
    }

    /// Микрофон: пока говоришь, текст появляется в поле; потом можно поправить и отправить.
    private func startDictation() {
        textBeforeDictation = trimmed
        notice = nil
        focused = false
        Task { await dictation.start() }
    }

    private func send() {
        if dictation.isRecording {
            dictation.stop()
        }
        if aiOn {
            askAI()
        } else {
            save()
        }
    }

    /// Фраза уходит в DeepSeek. Не вышло — она не теряется, а ложится во «Входящие».
    private func askAI() {
        let phrase = trimmed
        guard !phrase.isEmpty, !working else { return }
        let said = Date()
        text = ""
        notice = nil
        working = true
        Task {
            do {
                let content = try await AIService.ask(phrase, said: said)
                let result = try AIService.parse(content, said: said)
                working = false
                reviewPhrase = phrase
                reviewSaved = false
                review = AIReview(phrase: phrase, reply: result.reply, drafts: result.drafts)
                // Сеть есть — заодно разберём, что ждёт во «Входящих».
                InboxProcessor.shared.kick()
            } catch {
                working = false
                keepInInbox(phrase, said: said, problem: AIError.from(error))
            }
        }
    }

    private func keepInInbox(_ phrase: String, said: Date, problem: AIError) {
        let entry = InboxEntry(text: phrase, createdAt: said)
        if !problem.isTemporary && problem != .noKey {
            entry.lastError = problem.message
        }
        context.insert(entry)
        try? context.save()

        let message = problem.isTemporary
            ? "\(problem.message) — фраза во «Входящих», разберу позже"
            : "\(problem.message). Фраза — во «Входящих»"
        notice = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            if notice == message { notice = nil }
        }
    }

    /// Карточки закрыли без сохранения — фраза возвращается в поле, чтобы поправить.
    private func reviewClosed() {
        if !reviewSaved, let phrase = reviewPhrase, trimmed.isEmpty {
            text = phrase
        }
        reviewPhrase = nil
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
