import Foundation

/// Что ответить в Siri / на Кнопке действия.
enum QuickCaptureText {
    /// После записи: ответ ИИ, а если его нет — что именно записано.
    static func saved(_ drafts: [AIDraft], reply: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        let answer = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if !answer.isEmpty {
            return "Записал. \(answer)"
        }
        guard let first = drafts.first else { return "Записал." }
        if drafts.count > 1 {
            return "Записал \(drafts.count) \(RussianPlural.pick(drafts.count, "запись", "записи", "записей"))."
        }
        switch first.kind {
        case .reminder:
            if let due = first.due {
                return "Записал напоминание: \(first.title), \(DateText.short(due, now: now, calendar: calendar).lowercasedFirst)."
            }
            return "Записал дело без срока: \(first.title)."
        case .idea:
            return "Записал идею: \(first.title)."
        case .note:
            return "Записал заметку: \(first.title)."
        }
    }

    /// «Сегодня 2 дела: 09:00 Подойти к учителю, 13:30 Сдать пробник. Просрочено: 1.»
    static func today(_ entries: [SummaryPlanner.Entry], overdue: Int, calendar: Calendar = .current) -> String {
        var parts: [String] = []
        if entries.isEmpty {
            parts.append("На сегодня дел нет.")
        } else {
            let list = entries.prefix(SummaryPlanner.maxShown)
                .map { "\(DateText.timeString($0.date, calendar: calendar)) \($0.title)" }
                .joined(separator: ", ")
            var line = "Сегодня \(SummaryPlanner.countText(entries.count)): \(list)"
            if entries.count > SummaryPlanner.maxShown {
                line += " и ещё \(entries.count - SummaryPlanner.maxShown)"
            }
            parts.append(line + ".")
        }
        if overdue > 0 {
            parts.append("Просрочено: \(overdue).")
        }
        return parts.joined(separator: " ")
    }
}
