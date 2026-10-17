import SwiftUI

/// «Когда напомнить»: быстрые варианты и точная дата.
struct DueDateSheet: View {
    @Binding var selection: Date?
    @Binding var timeGiven: Bool

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.defaultHour) private var defaultHour = 9
    @AppStorage(SettingsKeys.defaultMinute) private var defaultMinute = 0
    @State private var custom = Date()

    var body: some View {
        let now = Date()
        let inHour = DateMath.inOneHour(from: now)
        let evening = DateMath.evening(from: now)
        let morning = DateMath.tomorrow(hour: defaultHour, minute: defaultMinute, from: now)

        NavigationStack {
            List {
                Section("Быстро") {
                    quickRow("Через час", inHour, given: true)
                    quickRow("Вечером", evening, given: true)
                    quickRow("Завтра утром", morning, given: false)
                }

                Section("Точная дата и время") {
                    DatePicker("Когда", selection: $custom, in: now..., displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                    Button("Напомнить \(DateText.short(custom).lowercasedFirst)") {
                        pick(custom, given: true)
                    }
                    .fontWeight(.semibold)
                }

                if selection != nil {
                    Section {
                        Button("Без срока", role: .destructive) {
                            selection = nil
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Когда напомнить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        .onAppear {
            custom = selection ?? morning
        }
    }

    private func quickRow(_ title: String, _ date: Date, given: Bool) -> some View {
        Button {
            pick(date, given: given)
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(Color.primary)
                Spacer()
                Text(DateText.short(date))
                    .foregroundStyle(Color.secondary)
            }
        }
    }

    private func pick(_ date: Date, given: Bool) {
        selection = date
        timeGiven = given
        dismiss()
    }
}
