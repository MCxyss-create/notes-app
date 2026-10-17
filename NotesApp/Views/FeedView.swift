import SwiftUI
import SwiftData

/// Лента напоминаний: Просрочено / Сегодня / Завтра / Позже / Без срока / Выполнено.
struct FeedView: View {
    var onEdit: (Item) -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]

    var body: some View {
        let reminders = items.filter { $0.kind == .reminder }
        if reminders.isEmpty {
            ContentUnavailableView(
                "Напоминаний нет",
                systemImage: "bell",
                description: Text("Напиши внизу, что сделать, и выбери время — я напомню.")
            )
        } else {
            // Раз в минуту пересчитываем блоки: дело само переедет в «Просрочено».
            TimelineView(.everyMinute) { timeline in
                list(groups: FeedGrouping.group(reminders, now: timeline.date), now: timeline.date)
            }
        }
    }

    private func list(groups: [FeedGroup<Item>], now: Date) -> some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.section == .done ? Array(group.items.prefix(30)) : group.items) { item in
                        row(item, now: now)
                    }
                } header: {
                    HStack {
                        Text(group.section.title)
                        Spacer()
                        Text("\(group.items.count)")
                    }
                    .foregroundStyle(group.section == .overdue ? Color.red : Color.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    private func row(_ item: Item, now: Date) -> some View {
        ItemRow(item: item, now: now, onToggle: { toggleDone(item) })
            .contentShape(Rectangle())
            .onTapGesture { onEdit(item) }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    toggleDone(item)
                } label: {
                    Label(item.isDone ? "Вернуть" : "Готово",
                          systemImage: item.isDone ? "arrow.uturn.backward" : "checkmark")
                }
                .tint(.green)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                // Повторяющееся дело не откладываем: сдвинулся бы весь повтор.
                if !item.isDone && item.repeatRule == nil {
                    Button {
                        snooze(item, .tomorrow)
                    } label: {
                        Label("Завтра", systemImage: "sunrise")
                    }
                    .tint(.blue)

                    Button {
                        snooze(item, .evening)
                    } label: {
                        Label("Вечером", systemImage: "moon")
                    }
                    .tint(.indigo)

                    Button {
                        snooze(item, .hour)
                    } label: {
                        Label("+1 час", systemImage: "clock")
                    }
                    .tint(.orange)
                }
            }
            .contextMenu {
                Button {
                    onEdit(item)
                } label: {
                    Label("Изменить", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    withAnimation { context.delete(item) }
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
    }

    /// Повторяющееся дело при «Готово» переезжает на следующий раз.
    private func toggleDone(_ item: Item) {
        withAnimation {
            ItemActions.toggleDone(item)
        }
    }

    private func snooze(_ item: Item, _ option: SnoozeOption) {
        withAnimation {
            ItemActions.snooze(item, option)
        }
    }
}
