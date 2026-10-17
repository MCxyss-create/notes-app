import Foundation
import SwiftData

/// Одна запись: заметка, идея или напоминание. Хранится только на телефоне.
@Model
final class Item {
    @Attribute(.unique) var uid: UUID = UUID()
    var kindRaw: String = "note"
    var title: String = ""
    var body: String?
    var createdAt: Date = Date()
    var dueAt: Date?
    var timeGiven: Bool = true
    var remindBeforeMin: Int?
    var repeatRaw: String?
    var isDone: Bool = false
    var doneAt: Date?
    var tags: [String] = []
    var isPinned: Bool = false
    var rawInput: String?
    var sourceRaw: String = "manual"

    init(
        kind: ItemKind,
        title: String,
        body: String? = nil,
        createdAt: Date = Date(),
        dueAt: Date? = nil,
        timeGiven: Bool = true,
        remindBeforeMin: Int? = nil,
        repeatRule: RepeatRule? = nil,
        isDone: Bool = false,
        doneAt: Date? = nil,
        tags: [String] = [],
        isPinned: Bool = false,
        rawInput: String? = nil,
        source: ItemSource = .manual
    ) {
        self.uid = UUID()
        self.kindRaw = kind.rawValue
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.dueAt = dueAt
        self.timeGiven = timeGiven
        self.remindBeforeMin = remindBeforeMin
        self.repeatRaw = repeatRule?.rawValue
        self.isDone = isDone
        self.doneAt = doneAt
        self.tags = tags
        self.isPinned = isPinned
        self.rawInput = rawInput
        self.sourceRaw = source.rawValue
    }

    var kind: ItemKind {
        get { ItemKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    var repeatRule: RepeatRule? {
        get { repeatRaw.flatMap { RepeatRule(rawValue: $0) } }
        set { repeatRaw = newValue?.rawValue }
    }

    var source: ItemSource {
        get { ItemSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}

extension Item: FeedGroupable {}

extension ReminderInput {
    init(item: Item) {
        self.init(
            id: item.uid,
            title: item.title,
            details: item.body,
            dueAt: item.dueAt,
            remindBeforeMin: item.remindBeforeMin,
            isDone: item.isDone,
            repeatRule: item.repeatRule
        )
    }
}
