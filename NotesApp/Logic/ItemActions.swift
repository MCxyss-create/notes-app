import Foundation

/// Действия над записью — одни и те же из ленты, редактирования и кнопок в уведомлении.
enum ItemActions {
    /// «Готово». Повторяющееся дело не закрывается, а переезжает на следующий раз.
    static func complete(_ item: Item, now: Date = Date(), calendar: Calendar = .current) {
        if item.kind == .reminder, let rule = item.repeatRule, let due = item.dueAt {
            item.dueAt = RepeatMath.next(after: due, rule: rule, now: now, calendar: calendar)
            item.isDone = false
            item.doneAt = nil
        } else {
            item.isDone = true
            item.doneAt = now
        }
    }

    /// Кружок и свайп вправо: выполнено ↔ вернуть.
    static func toggleDone(_ item: Item, now: Date = Date()) {
        if item.isDone {
            item.isDone = false
            item.doneAt = nil
        } else {
            complete(item, now: now)
        }
    }

    /// «+1 час», «Вечером», «Завтра». Повторяющиеся дела не откладываются.
    static func snooze(_ item: Item, _ option: SnoozeOption, now: Date = Date()) {
        guard item.repeatRule == nil else { return }
        item.dueAt = DateMath.snooze(
            option,
            due: item.dueAt,
            timeGiven: item.timeGiven,
            defaultHour: AppDefaults.hour,
            defaultMinute: AppDefaults.minute,
            now: now
        )
        if option != .tomorrow { item.timeGiven = true }
        item.isDone = false
        item.doneAt = nil
    }
}
