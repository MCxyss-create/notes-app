import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKeys.defaultHour) private var defaultHour = 9
    @AppStorage(SettingsKeys.defaultMinute) private var defaultMinute = 0
    @AppStorage(SettingsKeys.defaultBeforeMin) private var defaultBefore = 15
    @AppStorage(SettingsKeys.aiEndpoint) private var aiEndpoint = ""
    @AppStorage(SettingsKeys.aiModel) private var aiModel = ""
    @AppStorage(SettingsKeys.morningSummaryOn) private var morningOn = SummarySettings.standard.morningOn
    @AppStorage(SettingsKeys.morningSummaryMinutes) private var morningMinutes = SummarySettings.standard.morningMinutes
    @AppStorage(SettingsKeys.eveningSummaryOn) private var eveningOn = SummarySettings.standard.eveningOn
    @AppStorage(SettingsKeys.eveningSummaryMinutes) private var eveningMinutes = SummarySettings.standard.eveningMinutes
    @State private var keyInput = ""
    @State private var savedKey: String?
    @State private var keyMessage: String?
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var pending = 0
    @State private var testMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                aiSection

                notificationsSection

                summarySection

                Section {
                    DatePicker("Время для «завтра»", selection: defaultTime, displayedComponents: .hourAndMinute)
                    Picker("Напоминать заранее", selection: $defaultBefore) {
                        ForEach(BeforeOption.all, id: \.minutes) { option in
                            Text(option.title).tag(option.minutes)
                        }
                    }
                } header: {
                    Text("По умолчанию")
                } footer: {
                    Text("Если указан только день, напоминание сработает в это время.")
                }

                Section("О приложении") {
                    LabeledContent("Версия", value: AppInfo.versionText)
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .task {
                await refresh()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await refresh() }
                }
            }
        }
    }

    private var aiSection: some View {
        Section {
            if let savedKey {
                LabeledContent("Ключ", value: "••••" + String(savedKey.suffix(4)))
                Button("Удалить ключ", role: .destructive) {
                    KeychainStore.delete(AISettings.keyAccount)
                    self.savedKey = nil
                    keyMessage = nil
                }
            } else {
                SecureField("Ключ API (sk-…)", text: $keyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Сохранить ключ") {
                    saveKey()
                }
                .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let keyMessage {
                Text(keyMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Адрес API")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                TextField("Адрес API", text: $aiEndpoint, prompt: Text(AIConfig.defaultEndpoint))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Модель")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                TextField("Модель", text: $aiModel, prompt: Text(AIConfig.defaultModel))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            NavigationLink("Проверить разбор: 8 фраз") {
                AICheckView()
            }
        } header: {
            Text("ИИ DeepSeek")
        } footer: {
            Text("Ключ хранится в связке ключей iPhone. Фраза уходит в DeepSeek, только когда у поля ввода включена ✨. Пустые адрес и модель — значения по умолчанию.")
        }
    }

    private func saveKey() {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if KeychainStore.save(key, account: AISettings.keyAccount) {
            savedKey = key
            keyInput = ""
            keyMessage = "Ключ сохранён. Проверь его: «Проверить разбор»."
            Task { await InboxProcessor.shared.keyChanged() }
        } else {
            keyMessage = "Не удалось сохранить ключ в связку ключей."
        }
    }

    private var notificationsSection: some View {
        Section {
            LabeledContent("Разрешение") {
                Text(statusText)
                    .foregroundStyle(statusColor)
            }
            if status == .notDetermined {
                Button("Разрешить уведомления") {
                    Task {
                        await NotificationService.shared.requestIfNeeded()
                        await refresh()
                    }
                }
            }
            if status == .denied {
                Button("Открыть настройки iPhone") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            LabeledContent("Запланировано", value: "\(pending)")
            Button("Проверить: уведомление через минуту") {
                Task { await sendTest() }
            }
            if let testMessage {
                Text(testMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
        } header: {
            Text("Уведомления")
        }
    }

    private var summarySection: some View {
        Section {
            Toggle("Утренняя сводка", isOn: $morningOn)
            if morningOn {
                DatePicker("Во сколько", selection: minutesBinding($morningMinutes), displayedComponents: .hourAndMinute)
            }
            Toggle("План на завтра вечером", isOn: $eveningOn)
            if eveningOn {
                DatePicker("Во сколько", selection: minutesBinding($eveningMinutes), displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Сводки")
        } footer: {
            Text("Утром — что сегодня, вечером — что завтра. Приходят, только когда есть дела.")
        }
    }

    /// Время сводки хранится минутами от полуночи.
    private func minutesBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { DateMath.atTime(Date(), hour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private var statusText: String {
        switch status {
        case .authorized: return "Разрешены"
        case .denied: return "Запрещены"
        case .notDetermined: return "Не спрашивали"
        case .provisional: return "Тихие"
        case .ephemeral: return "Временные"
        @unknown default: return "—"
        }
    }

    private var statusColor: Color {
        switch status {
        case .authorized: return .green
        case .denied: return .red
        default: return .orange
        }
    }

    private var defaultTime: Binding<Date> {
        Binding(
            get: { DateMath.atTime(Date(), hour: defaultHour, minute: defaultMinute) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                defaultHour = parts.hour ?? 9
                defaultMinute = parts.minute ?? 0
            }
        )
    }

    private func refresh() async {
        savedKey = AISettings.apiKey
        status = await NotificationService.shared.status()
        pending = await NotificationService.shared.pendingCount()
    }

    private func sendTest() async {
        let allowed = await NotificationService.shared.requestIfNeeded()
        guard allowed else {
            testMessage = "Уведомления запрещены — включи их в настройках iPhone."
            await refresh()
            return
        }
        do {
            try await NotificationService.shared.scheduleTest(after: 60)
            testMessage = "Через минуту придёт уведомление. Можно закрыть приложение и заблокировать телефон."
        } catch {
            testMessage = "Не получилось: \(error.localizedDescription)"
        }
        await refresh()
    }
}
