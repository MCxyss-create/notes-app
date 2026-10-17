import SwiftUI
import SwiftData

/// Разделы приложения. Переключаются вкладками сверху:
/// горизонтальный свайп по строке занят «выполнено / отложить».
enum MainPage: String, CaseIterable, Identifiable {
    case feed
    case ideas
    case notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feed: return "Лента"
        case .ideas: return "Идеи"
        case .notes: return "Заметки"
        }
    }

    var kind: ItemKind {
        switch self {
        case .feed: return .reminder
        case .ideas: return .idea
        case .notes: return .note
        }
    }
}

struct RootView: View {
    let demo: DemoConfig?

    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Item.createdAt) private var allItems: [Item]
    @State private var page: MainPage = .feed
    @State private var showSettings = false
    @State private var editing: Item?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Раздел", selection: $page) {
                    ForEach(MainPage.allCases) { p in
                        Text(p.title).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ComposerBar(
                    defaultKind: page.kind,
                    autoFocus: demo == nil,
                    demoShowDue: demo?.screen == .due
                )
            }
            .navigationTitle("Мысли")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Настройки")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(item: $editing) { item in
                EditItemView(item: item)
            }
        }
        .onChange(of: signature) {
            reschedule()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reschedule() }
        }
        .task {
            await start()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .feed:
            FeedView(onEdit: { editing = $0 })
        case .ideas:
            ItemListView(kind: .idea, onEdit: { editing = $0 })
        case .notes:
            ItemListView(kind: .note, onEdit: { editing = $0 })
        }
    }

    /// Меняется при любой правке записей → уведомления пересчитываются сами.
    private var signature: Int {
        var hasher = Hasher()
        for item in allItems {
            hasher.combine(item.uid)
            hasher.combine(item.kindRaw)
            hasher.combine(item.title)
            hasher.combine(item.body)
            hasher.combine(item.dueAt)
            hasher.combine(item.isDone)
            hasher.combine(item.remindBeforeMin)
        }
        return hasher.finalize()
    }

    private func start() async {
        if let demo {
            try? await Task.sleep(nanoseconds: 400_000_000)
            applyDemo(demo)
            return
        }
        if AppEnvironment.isRunningTests { return }
        await NotificationService.shared.requestIfNeeded()
        reschedule()
    }

    private func reschedule() {
        guard demo == nil, !AppEnvironment.isRunningTests else { return }
        let reminders = allItems
            .filter { $0.kind == .reminder }
            .map { ReminderInput(item: $0) }
        NotificationService.shared.reschedule(NotificationPlanner.plan(reminders, now: Date()))
    }

    private func applyDemo(_ demo: DemoConfig) {
        switch demo.screen {
        case .feed, .due, .empty:
            break
        case .ideas:
            page = .ideas
        case .notes:
            page = .notes
        case .settings:
            showSettings = true
        case .edit:
            editing = allItems.first { $0.title == DemoData.editTitle }
        }
    }
}
