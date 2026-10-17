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
                 remindBeforeMin: 15, rawInput: "завтра подойти к учителю, спросить про пробник", source: .ai),
            Item(kind: .reminder, title: "Сдать пробник", dueAt: day(1, 13, 30), remindBeforeMin: 30),
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
        try? context.save()
    }
}
