import SwiftUI
import SwiftData

/// Строка записи в списке. Есть фото — справа миниатюра первого, под заголовком 📷 с числом.
struct ItemRow: View {
    let item: Item
    let now: Date
    var onToggle: (() -> Void)? = nil

    @Query private var photos: [PhotoAttachment]

    init(item: Item, now: Date, onToggle: (() -> Void)? = nil) {
        self.item = item
        self.now = now
        self.onToggle = onToggle
        let id = item.uid
        _photos = Query(filter: #Predicate<PhotoAttachment> { $0.itemID == id }, sort: \.sortIndex)
    }

    private var isOverdue: Bool {
        guard !item.isDone, let due = item.dueAt else { return false }
        return due < now
    }

    /// «Завтра, 09:00» или «Завтра, 09:00 · каждый день».
    private func dueText(_ due: Date) -> String {
        let text = DateText.short(due, now: now)
        guard let rule = item.repeatRule else { return text }
        return "\(text) · \(rule.title.lowercasedFirst)"
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
                    Label(dueText(due), systemImage: item.repeatRule == nil ? "clock" : "repeat")
                        .font(.caption)
                        .foregroundStyle(isOverdue ? Color.red : Color.secondary)
                } else if item.kind != .reminder {
                    Text(DateText.short(item.createdAt, now: now))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }

                if !item.tags.isEmpty {
                    Text(TagText.display(item.tags))
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }

                if !photos.isEmpty {
                    Label("\(photos.count)", systemImage: "camera")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }

            Spacer(minLength: 0)

            if let first = photos.first {
                PhotoThumb(data: first.thumbData, size: 44, corner: 8)
                    .accessibilityLabel("Фото: \(photos.count)")
            }
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
