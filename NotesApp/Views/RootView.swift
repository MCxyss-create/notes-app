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
    @Environment(\.modelContext) private var context
    @Query(sort: \Item.createdAt) private var allItems: [Item]
    @Query(sort: \InboxEntry.createdAt) private var inbox: [InboxEntry]
    @State private var page: MainPage = .feed
    @State private var showSettings = false
    @State private var showInbox = false
    /// Открытый поиск и с каким запросом. Через item, чтобы запрос не терялся при открытии.
    @State private var search: SearchRequest?
    @State private var editing: Item?
    /// Приложение уходило в фон — при возвращении снова слушать.
    @State private var wasAway = false
    @AppStorage(SettingsKeys.listenOnOpen) private var listenOnOpen = true

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

                if !inbox.isEmpty {
                    inboxBanner
                }

                if let expiry = ProvisionInfo.expirationDate,
                   ResignPlanner.needsBanner(expiration: expiry, now: Date()) {
                    resignBanner(expiry)
                }

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ComposerBar(
                    defaultKind: page.kind,
                    autoFocus: demo == nil,
                    demoShowDue: demo?.screen == .due,
                    demoReview: demo?.screen == .review ? DemoData.review()
                        : demo?.screen == .command ? DemoData.commandReview() : nil,
                    demoListening: demo?.screen == .listen
                )
            }
            .navigationTitle("Мысли")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        search = SearchRequest(query: "")
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Поиск")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Настройки")
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: reschedule) {
                SettingsView()
            }
            .sheet(item: $editing) { item in
                EditItemView(item: item)
            }
            .sheet(isPresented: $showInbox) {
                InboxView()
            }
            .sheet(item: $search) { request in
                SearchView(initialQuery: request.query)
            }
        }
        .onChange(of: signature) {
            reschedule()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                reschedule()
                InboxProcessor.shared.kick()
                if wasAway {
                    wasAway = false
                    listenAgain()
                }
            } else if phase == .background {
                wasAway = true
            }
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

    /// Фразы, которые ИИ не разобрал сразу. Разобранные ждут подтверждения.
    private var inboxBanner: some View {
        let ready = inbox.filter { $0.parsedJSON != nil }.count
        return Button {
            showInbox = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: ready > 0 ? "tray.full.fill" : "tray.full")
                Text("Входящие: \(inbox.count)")
                    .fontWeight(.semibold)
                if ready > 0 {
                    Text("· разобрано \(ready)")
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .font(.subheadline)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Бесплатная подпись скоро кончится — после этого приложение не откроется до переустановки.
    private func resignBanner(_ expiry: Date) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Подпись кончится \(DateText.short(expiry).lowercasedFirst). Переустанови через iloader — записи сохранятся.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
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
            hasher.combine(item.repeatRaw)
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
        InboxProcessor.shared.start(context: context)
        await NotificationService.shared.requestIfNeeded()
        reschedule()
    }

    /// Вернулся в приложение — микрофон снова слушает, если поверх ничего не открыто.
    private func listenAgain() {
        guard listenOnOpen, demo == nil, !AppEnvironment.isRunningTests,
              !showSettings, !showInbox, search == nil, editing == nil,
              QuickLaunch.shared.pending == nil else { return }
        QuickLaunch.shared.request(.listen)
    }

    private func reschedule() {
        guard demo == nil, !AppEnvironment.isRunningTests else { return }
        NotificationScheduler.rescheduleAll(items: allItems)
    }

    private func applyDemo(_ demo: DemoConfig) {
        switch demo.screen {
        case .feed, .due, .empty, .review, .listen, .command:
            break
        case .inbox:
            showInbox = true
        case .search:
            search = SearchRequest(query: "#школа")
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
