import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKeys.defaultHour) private var defaultHour = 9
    @AppStorage(SettingsKeys.defaultMinute) private var defaultMinute = 0
    @AppStorage(SettingsKeys.defaultBeforeMin) private var defaultBefore = 15
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var pending = 0
    @State private var testMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                notificationsSection

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
