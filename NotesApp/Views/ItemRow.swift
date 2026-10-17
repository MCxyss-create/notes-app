import SwiftUI

/// Строка записи в списке.
struct ItemRow: View {
    let item: Item
    let now: Date
    var onToggle: (() -> Void)? = nil

    private var isOverdue: Bool {
        guard !item.isDone, let due = item.dueAt else { return false }
        return due < now
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leadingIcon
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(Color.orange)
                    }
                    Text(item.title)
                        .strikethrough(item.isDone)
                        .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                }

                if let details = item.body, !details.isEmpty {
                    Text(details)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                }

                if item.kind == .reminder, let due = item.dueAt {
                    Label(DateText.short(due, now: now), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(isOverdue ? Color.red : Color.secondary)
                } else if item.kind != .reminder {
                    Text(DateText.short(item.createdAt, now: now))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if item.kind == .reminder {
            Button {
                onToggle?()
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(item.isDone ? "Вернуть" : "Выполнено")
        } else {
            Image(systemName: item.kind.symbol)
                .font(.title3)
                .foregroundStyle(Color.secondary)
        }
    }
}
