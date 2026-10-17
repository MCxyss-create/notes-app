import Foundation
import SwiftData

/// Демо-режим для снимков экранов в GitHub: приложение запускается с `-demo <экран>`,
/// берёт базу в памяти с примерами и сразу открывает нужный экран.
struct DemoConfig: Equatable {
    enum Screen: String {
        case feed
        case due
        case edit
        case ideas
        case notes
        case settings
        case empty
        case review
        case inbox
    }

    let screen: Screen

    static func fromLaunchArguments() -> DemoConfig? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-demo"), index + 1 < args.count,
              let screen = Screen(rawValue: args[index + 1]) else { return nil }
        return DemoConfig(screen: screen)
    }
}

enum DemoData {
    static let editTitle = "Подойти к учителю"

    @MainActor
    static func seed(into context: ModelContext, screen: DemoConfig.Screen) {
        guard screen != .empty else { return }
        let calendar = Calendar.current
        let now = Date()

        func day(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let d = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            return DateMath.atTime(d, hour: hour, minute: minute, calendar: calendar)
        }

        let items: [Item] = [
            Item(kind: .reminder, title: "Оплатить интернет", dueAt: now.addingTimeInterval(-3 * 3600), remindBeforeMin: 15),
            Item(kind: .reminder, title: "Позвонить маме", dueAt: now.addingTimeInterval(40 * 60), remindBeforeMin: 15),
            Item(kind: .reminder, title: editTitle, body: "Спросить про пробник", dueAt: day(1, 9), timeGiven: false,
                 remindBeforeMin: 15, tags: ["школа"], rawInput: "завтра подойти к учителю, спросить про пробник", source: .ai),
            Item(kind: .reminder, title: "Сдать пробник", dueAt: day(1, 13, 30), remindBeforeMin: 30, tags: ["школа"]),
            Item(kind: .reminder, title: "Выпить витамины", dueAt: day(1, 8), remindBeforeMin: nil, repeatRule: .daily),
            Item(kind: .reminder, title: "Забрать посылку", dueAt: day(4, 15), remindBeforeMin: 60),
            Item(kind: .reminder, title: "Купить шнурки"),
            Item(kind: .reminder, title: "Отправить домашку", isDone: true, doneAt: now.addingTimeInterval(-3600)),
            Item(kind: .idea, title: "Бот, который сам считает расходы", body: "Пишу «кофе 250» — он записывает в таблицу", isPinned: true),
            Item(kind: .idea, title: "Тёмная тема для приложения"),
            Item(kind: .idea, title: "Виджет с ближайшим делом", createdAt: now.addingTimeInterval(-2 * 86_400)),
            Item(kind: .note, title: "Размер ноги — 43 EU"),
            Item(kind: .note, title: "Пароль от Wi-Fi на даче", body: "Написан на роутере снизу", createdAt: now.addingTimeInterval(-86_400)),
        ]
        for item in items {
            context.insert(item)
        }
        if screen == .inbox {
            for entry in inboxEntries(now: now) {
                context.insert(entry)
            }
        }
        try? context.save()
    }

    /// Карточки «вот что я понял» для снимка: ответ модели разбирает настоящий AIParser.
    static func review(now: Date = Date()) -> AIReview {
        let phrase = "в 7 вечера оплатить сервер и завтра утром сдать пробник, идея: бот для отчётов"
        let json = """
        {"items":[
          {"kind":"reminder","title":"Оплатить сервер","body":null,"due":"\(tomorrowISO(19, now: now))","time_given":true,"remind_before_min":15,"repeat":null,"tags":["сервер"]},
          {"kind":"reminder","title":"Сдать пробник","body":null,"due":"\(tomorrowISO(9, now: now))","time_given":true,"remind_before_min":15,"repeat":null,"tags":["школа"]},
          {"kind":"idea","title":"Бот для отчётов","body":"Сам собирает отчёт за неделю","due":null,"time_given":false,"remind_before_min":null,"repeat":null,"tags":[]}
        ],"reply":"Два напоминания на завтра и одна идея."}
        """
        let result = (try? AIParser.parse(json, reference: now, now: now,
                                          defaults: ParseDefaults(hour: 9, minute: 0, beforeMin: 15),
                                          calendar: AISettings.calendar))
            ?? AIResult(reply: "Демо-ответ не разобрался", drafts: [])
        return AIReview(phrase: phrase, reply: result.reply, drafts: result.drafts)
    }

    private static func inboxEntries(now: Date) -> [InboxEntry] {
        let parsed = InboxEntry(text: "завтра в 12 забрать куртку из химчистки", createdAt: now.addingTimeInterval(-3 * 3600))
        parsed.parsedJSON = """
        {"items":[{"kind":"reminder","title":"Забрать куртку из химчистки","due":"\(tomorrowISO(12, now: now))","time_given":true,"remind_before_min":15,"tags":[]}],"reply":"Напоминание на завтра, 12:00."}
        """
        let waiting = InboxEntry(text: "идея: напоминать пить воду каждые два часа", createdAt: now.addingTimeInterval(-20 * 60))
        let failed = InboxEntry(text: "купить подарок Лёше до среды", createdAt: now.addingTimeInterval(-26 * 3600))
        failed.lastError = AIError.http(401, nil).message
        return [failed, parsed, waiting]
    }

    private static func tomorrowISO(_ hour: Int, now: Date) -> String {
        let calendar = AISettings.calendar
        let day = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: DateMath.atTime(day, hour: hour, minute: 0, calendar: calendar))
    }
}
