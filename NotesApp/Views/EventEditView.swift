import SwiftData
import SwiftUI

/// Что открыть в форме события: новое (на день) или своё.
enum EventEditRequest: Identifiable {
    case new(month: Int, day: Int)
    case edit(CalendarEvent)

    var id: String {
        switch self {
        case .new(let month, let day): return "new-\(month)-\(day)"
        case .edit(let event): return event.uid.uuidString
        }
    }
}

/// Форма события в календаре: сохранить, отменить, удалить (с вопросом).
/// Своего NavigationStack нет — листом её оборачивают, в списке дня она открывается внутри.
struct EventEditView: View {
    let request: EventEditRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var draft: EventDraft

    init(request: EventEditRequest) {
        self.request = request
        switch request {
        case .new(let month, let day):
            _draft = State(initialValue: EventDraft(type: .birthday, title: "", month: month, day: day))
        case .edit(let event):
            _draft = State(initialValue: event.draft)
        }
    }

    private var event: CalendarEvent? {
        if case .edit(let event) = request { return event }
        return nil
    }

    var body: some View {
        EventForm(draft: $draft, onDelete: event == nil ? nil : delete)
            .navigationTitle(event == nil ? "Новое событие" : "Событие")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(!draft.isValid)
                }
            }
    }

    private func save() {
        if let event {
            event.apply(draft)
        } else {
            let created = CalendarEvent(type: draft.type, title: "", month: draft.month, day: draft.day)
            created.apply(draft)
            context.insert(created)
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        guard let event else { return }
        context.delete(event)
        try? context.save()
        dismiss()
    }
}

/// Поля события: вид, имя, день и месяц, год, заметка, «Напомнить» и время.
/// Та же форма правит событие на карточке «Вот что я понял».
struct EventForm: View {
    @Binding var draft: EventDraft
    var onDelete: (() -> Void)? = nil

    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                Picker("Вид", selection: $draft.type) {
                    ForEach(EventType.allCases) { type in
                        Label(type.title, systemImage: type.symbol).tag(type)
                    }
                }
                TextField(draft.type == .birthday ? "Имя: Лёша, мама" : "Название", text: $draft.title)
                    .font(.headline)
            }

            Section {
                Picker("День", selection: $draft.day) {
                    ForEach(1...31, id: \.self) { day in
                        Text("\(day)").tag(day)
                    }
                }
                Picker("Месяц", selection: $draft.month) {
                    ForEach(1...12, id: \.self) { month in
                        Text(CalendarMath.monthsNominative[month - 1]).tag(month)
                    }
                }
                LabeledContent("Год") {
                    TextField("необязательно", text: yearBinding)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Дата")
            } footer: {
                if !CalendarMath.isValid(month: draft.month, day: draft.day) {
                    Text("Такой даты нет")
                        .foregroundStyle(Color.red)
                } else {
                    Text("Каждый год. С годом покажу возраст: «исполнится 18».")
                }
            }

            Section("Заметка") {
                TextField("Например: что подарить", text: noteBinding, axis: .vertical)
                    .lineLimit(1...4)
            }

            Section {
                ForEach(CalendarMath.remindOptions, id: \.self) { days in
                    Toggle(optionTitle(days), isOn: remindBinding(days))
                }
                DatePicker("Время", selection: timeBinding, displayedComponents: .hourAndMinute)
            } header: {
                Text("Напомнить")
            }

            if onDelete != nil {
                Section {
                    Button("Удалить", role: .destructive) {
                        confirmDelete = true
                    }
                }
            }
        }
        .keyboardDismissable()
        .confirmationDialog("Удалить событие?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                onDelete?()
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func optionTitle(_ days: Int) -> String {
        switch days {
        case 0: return "В день"
        case 1: return "За день"
        case 7: return "За неделю"
        default: return "За \(days) \(RussianPlural.pick(days, "день", "дня", "дней"))"
        }
    }

    private func remindBinding(_ days: Int) -> Binding<Bool> {
        Binding(
            get: { draft.remindDays.contains(days) },
            set: { on in
                var set = Set(draft.remindDays)
                if on { set.insert(days) } else { set.remove(days) }
                draft.remindDays = set.sorted()
            }
        )
    }

    private var yearBinding: Binding<String> {
        Binding(
            get: { draft.year.map(String.init) ?? "" },
            set: { text in
                let digits = String(text.filter(\.isNumber).prefix(4))
                draft.year = Int(digits).flatMap { (1...9999).contains($0) ? $0 : nil }
            }
        )
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { draft.note ?? "" },
            set: { draft.note = $0.isEmpty ? nil : $0 }
        )
    }

    /// Время напоминания. Не трогали — берётся из настроек (nil).
    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                let minutes = draft.remindMinutes ?? CalendarSettings.defaultMinutes
                return DateMath.atTime(Date(), hour: minutes / 60, minute: minutes % 60)
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft.remindMinutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
            }
        )
    }
}
