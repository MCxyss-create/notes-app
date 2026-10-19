import Foundation
import SwiftData
import UIKit

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
        case search
        case listen
        case command
        /// Открытая клавиатура: главный экран, карточка записи, поиск.
        case keyboard
        case editKeyboard
        case searchKeyboard
        /// Настройки, блок «Чтобы «Мысли» были сверху» (срочные уведомления).
        case urgent
        /// «Идеи» с разделом папок и папка «Проекты / VPN» с вложенной «Реклама».
        case folders
        case folder
        /// Карточка идеи с 3 фото и это фото на весь экран.
        case photos
        case viewer
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
    static let folderVPN = "VPN"
    static let photoTitle = "Бот, который сам считает расходы"
    /// Что «слышит» микрофон на снимке «Слушаю».
    static let listeningText = "перенеси учителя на понедельник и маме позвонил"

    /// Демо-фото: цветной градиент с подписью, 1600×1200.
    @MainActor
    static func samplePhoto(_ caption: String, from top: UIColor, to bottom: UIColor) -> UIImage {
        let size = CGSize(width: 1600, height: 1200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height),
                                                     options: [])
            }
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 120, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: style,
            ]
            (caption as NSString).draw(in: CGRect(x: 80, y: size.height / 2 - 80, width: size.width - 160, height: 300),
                                       withAttributes: attributes)
        }
    }

    /// Снимки с клавиатурой: курсор в верхнее поле верхнего экрана (открытого листа, если он есть).
    @MainActor
    static func focusTopField() {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        guard var top = window?.rootViewController else { return }
        while let presented = top.presentedViewController {
            top = presented
        }
        var fields: [UIView] = []
        collectFields(in: top.view, into: &fields)
        let field = fields.min { $0.convert(CGPoint.zero, to: nil).y < $1.convert(CGPoint.zero, to: nil).y }
        field?.becomeFirstResponder()
    }

    @MainActor
    private static func collectFields(in view: UIView, into fields: inout [UIView]) {
        if view is UITextField || view is UITextView {
            fields.append(view)
            return
        }
        for sub in view.subviews {
            collectFields(in: sub, into: &fields)
        }
    }

    @MainActor
    static func seed(into context: ModelContext, screen: DemoConfig.Screen) {
        guard screen != .empty else { return }
        let calendar = Calendar.current
        let now = Date()

        func day(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let d = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            return DateMath.atTime(d, hour: hour, minute: minute, calendar: calendar)
        }

        // Папки: Проекты → VPN → Реклама и Школа.
        let projects = Folder(name: "Проекты", color: .blue, symbol: "briefcase", sortIndex: 0)
        let vpn = Folder(name: folderVPN, color: .green, symbol: "folder", parentID: projects.uid, sortIndex: 1)
        let ads = Folder(name: "Реклама", color: .orange, symbol: "star", parentID: vpn.uid, sortIndex: 2)
        let school = Folder(name: "Школа", color: .purple, symbol: "graduationcap", sortIndex: 3)
        for folder in [projects, vpn, ads, school] {
            context.insert(folder)
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
            Item(kind: .idea, title: photoTitle, body: "Пишу «кофе 250» — он записывает в таблицу", isPinned: true),
            Item(kind: .idea, title: "Тёмная тема для приложения"),
            Item(kind: .idea, title: "Виджет с ближайшим делом", createdAt: now.addingTimeInterval(-2 * 86_400),
                 folderID: projects.uid),
            Item(kind: .idea, title: "Свой сервер в Финляндии", createdAt: now.addingTimeInterval(-3600), folderID: vpn.uid),
            Item(kind: .note, title: "Тариф — 199 ₽ в месяц", body: "Пробный период 3 дня",
                 createdAt: now.addingTimeInterval(-5 * 3600), folderID: vpn.uid),
            Item(kind: .idea, title: "Реклама у блогеров", createdAt: now.addingTimeInterval(-7200), folderID: ads.uid),
            Item(kind: .note, title: "Расписание звонков", body: "1 урок 8:30–9:15", folderID: school.uid),
            Item(kind: .note, title: "Размер ноги — 43 EU"),
            Item(kind: .note, title: "Пароль от Wi-Fi на даче", body: "Написан на роутере снизу", createdAt: now.addingTimeInterval(-86_400)),
        ]
        for item in items {
            context.insert(item)
        }
        // Фото рисуем в коде — картинок в репозитории нет.
        if let bot = items.first(where: { $0.title == photoTitle }) {
            let samples: [(String, UIColor, UIColor)] = [
                ("Чек из кофейни", .systemOrange, .systemPink),
                ("Таблица расходов", .systemTeal, .systemBlue),
                ("Схема бота", .systemPurple, .systemIndigo),
            ]
            let prepared = samples.compactMap { PhotoStore.prepare(image: samplePhoto($0.0, from: $0.1, to: $0.2)) }
            PhotoStore.add(prepared, to: bot.uid, context: context, now: now)
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

    /// Карточки команд для снимка: перенести, готово, удалить. Разбирает настоящий AIParser.
    static func commandReview(now: Date = Date()) -> AIReview {
        let calendar = AISettings.calendar
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        // Понедельник после завтрашнего дня: иначе в воскресенье «перенос» был бы на тот же день.
        var monday = calendar.date(byAdding: .day, value: 1, to: tomorrow) ?? tomorrow
        while calendar.component(.weekday, from: monday) != 2 {
            monday = calendar.date(byAdding: .day, value: 1, to: monday) ?? monday
        }
        let teacher = AIKnownItem(uid: UUID(), kind: .reminder, title: editTitle,
                                  due: DateMath.atTime(tomorrow, hour: 9, minute: 0, calendar: calendar), timeGiven: false)
        let mom = AIKnownItem(uid: UUID(), kind: .reminder, title: "Позвонить маме", due: now.addingTimeInterval(40 * 60))
        let wifi = AIKnownItem(uid: UUID(), kind: .note, title: "Пароль от Wi-Fi на даче")
        let phrase = "перенеси учителя на понедельник, маме позвонил и удали пароль от вайфая"
        let json = """
        {"items":[],"changes":[
          {"op":"move","id":"\(teacher.ref)","due":"\(AIPrompt.dayText(monday, calendar))","time_given":false},
          {"op":"done","id":"\(mom.ref)"},
          {"op":"delete","id":"\(wifi.ref)"}
        ],"reply":"Перенесу учителя, отмечу звонок и удалю пароль."}
        """
        let result = (try? AIParser.parse(json, reference: now, now: now,
                                          defaults: ParseDefaults(hour: 9, minute: 0, beforeMin: 15),
                                          calendar: calendar, known: [teacher, mom, wifi]))
            ?? AIResult(reply: "Демо-ответ не разобрался", drafts: [])
        return AIReview(phrase: phrase, reply: result.reply, drafts: result.drafts, changes: result.changes)
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
