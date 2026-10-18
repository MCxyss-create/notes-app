import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    /// Демо-снимок: сразу прокрутить к блоку «Чтобы «Мысли» были сверху».
    var demoUrgent = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @State private var exportDocument: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var backupMessage: String?
    @AppStorage(SettingsKeys.defaultHour) private var defaultHour = 9
    @AppStorage(SettingsKeys.defaultMinute) private var defaultMinute = 0
    @AppStorage(SettingsKeys.defaultBeforeMin) private var defaultBefore = 15
    @AppStorage(SettingsKeys.aiEndpoint) private var aiEndpoint = ""
    @AppStorage(SettingsKeys.aiModel) private var aiModel = ""
    @AppStorage(SettingsKeys.listenOnOpen) private var listenOnOpen = true
    @AppStorage(SettingsKeys.voiceAutoSend) private var voiceAutoSend = true
    @AppStorage(SettingsKeys.morningSummaryOn) private var morningOn = SummarySettings.standard.morningOn
    @AppStorage(SettingsKeys.morningSummaryMinutes) private var morningMinutes = SummarySettings.standard.morningMinutes
    @AppStorage(SettingsKeys.eveningSummaryOn) private var eveningOn = SummarySettings.standard.eveningOn
    @AppStorage(SettingsKeys.eveningSummaryMinutes) private var eveningMinutes = SummarySettings.standard.eveningMinutes
    @State private var keyInput = ""
    @State private var savedKey: String?
    @State private var keyMessage: String?
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var timeSensitive: UNNotificationSetting = .notSupported
    @State private var pending = 0
    @State private var testMessage: String?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    aiSection

                    voiceSection

                    notificationsSection

                    urgentSection

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

                    backupSection

                    Section {
                        LabeledContent("Версия", value: AppInfo.versionText)
                        LabeledContent("Подпись действует до",
                                       value: ProvisionInfo.expirationDate.map { DateText.short($0) } ?? "нет данных")
                    } header: {
                        Text("О приложении")
                    } footer: {
                        Text("Бесплатная подпись живёт 7 дней. За сутки до конца придёт напоминание переустановить приложение через iloader (Import IPA) — записи сохранятся.")
                    }
                }
                .task {
                    // Снимок «срочных»: блок ниже первого экрана — прокрутить к нему.
                    guard demoUrgent else { return }
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    proxy.scrollTo(Self.urgentAnchor, anchor: .center)
                }
            }
            .keyboardDismissable()
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

            NavigationLink("Проверить разбор: 8 фраз и 4 команды") {
                AICheckView()
            }
        } header: {
            Text("ИИ DeepSeek")
        } footer: {
            Text("Ключ хранится в связке ключей iPhone. Фраза уходит в DeepSeek, только когда у поля ввода включена ✨. Вместе с ней уходят заголовки и сроки несделанных записей — так ИИ понимает команды. Пустые адрес и модель — значения по умолчанию.")
        }
    }

    /// Как VoiceOS: открыл — слушает, замолчал — ИИ разбирает сам.
    private var voiceSection: some View {
        Section {
            Toggle("Слушать сразу при открытии", isOn: $listenOnOpen)
            Toggle("Замолчал — отправить самому", isOn: $voiceAutoSend)
        } header: {
            Text("Голос")
        } footer: {
            Text("Открыл «Мысли» — микрофон уже слушает, пока поле пустое. Замолчишь на пару секунд — фраза уйдёт в ИИ, он покажет карточку. Команды: «перенеси учителя на пятницу», «маме позвонил», «удали заметку про Wi-Fi», «что у меня завтра?». Пока идёт запись, музыка может стихнуть.")
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

    private static let urgentAnchor = "urgent"

    /// iOS сам сортирует уведомления по времени. «Срочные» хотя бы пробивают Фокус
    /// и дольше висят на экране блокировки.
    private var urgentSection: some View {
        Section {
            Text(urgentText)
                .foregroundStyle(urgentColor)
                .id(Self.urgentAnchor)
            VStack(alignment: .leading, spacing: 4) {
                Text("Настройки iPhone → Уведомления → «Мысли»:")
                Text("• «Срочные уведомления» — вкл")
                Text("• «Стиль баннеров» → «Постоянно»: баннер висит, пока не смахнёшь")
                Text("• в режимах Фокуса разрешить срочные уведомления")
            }
            .font(.subheadline)
            .foregroundStyle(Color.secondary)
            Button("Открыть настройки уведомлений") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } header: {
            Text("Чтобы «Мысли» были сверху")
        } footer: {
            Text("Закрепить уведомления одного приложения над другими iOS не даёт — они идут по времени. Срочные пробивают Фокус и «Не беспокоить» и дольше держатся на экране блокировки.")
        }
    }

    private var urgentText: String {
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return "Срочные: сначала разреши уведомления"
        }
        switch timeSensitive {
        case .enabled: return "Срочные: включены"
        case .disabled: return "Срочные: выключены — включи в настройках iPhone"
        case .notSupported: return "Срочные: недоступны — бесплатная подпись не дала разрешение"
        @unknown default: return "Срочные: —"
        }
    }

    private var urgentColor: Color {
        timeSensitive == .enabled && status == .authorized ? .green : .orange
    }

    private var backupSection: some View {
        Section {
            Button("Сохранить копию в «Файлы»") {
                prepareExport()
            }
            .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json,
                          defaultFilename: Backup.fileName()) { result in
                switch result {
                case .success:
                    backupMessage = "Копия сохранена."
                case .failure(let error):
                    backupMessage = "Не сохранилось: \(error.localizedDescription)"
                }
            }

            Button("Восстановить из копии") {
                showImporter = true
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                importBackup(result)
            }

            if let backupMessage {
                Text(backupMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
        } header: {
            Text("Резервная копия")
        } footer: {
            Text("Все записи одним файлом JSON. Восстановление добавляет только те записи, которых ещё нет.")
        }
    }

    private func prepareExport() {
        let items = (try? context.fetch(FetchDescriptor<Item>(sortBy: [SortDescriptor(\Item.createdAt)]))) ?? []
        do {
            exportDocument = BackupDocument(data: try Backup.encode(items.map { BackupItem(item: $0) }))
            backupMessage = nil
            showExporter = true
        } catch {
            backupMessage = "Не получилось собрать копию: \(error.localizedDescription)"
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            backupMessage = "Не открылось: \(error.localizedDescription)"
        case .success(let url):
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let file = try Backup.decode(try Data(contentsOf: url))
                let existing = Set(((try? context.fetch(FetchDescriptor<Item>())) ?? []).map(\.uid))
                let fresh = Backup.newItems(in: file, existing: existing)
                for backup in fresh {
                    context.insert(backup.makeItem())
                }
                try? context.save()
                backupMessage = "Добавлено: \(fresh.count). Уже были: \(file.items.count - fresh.count)."
            } catch {
                backupMessage = "Это не копия «Мыслей» или файл повреждён."
            }
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
        timeSensitive = await NotificationService.shared.timeSensitive()
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
