import Foundation

/// Системный промт для DeepSeek: правила разбора, текущие дата и время, день недели, часовой пояс.
enum AIPrompt {
    static let weekdays = ["воскресенье", "понедельник", "вторник", "среда", "четверг", "пятница", "суббота"]

    static func system(now: Date, calendar: Calendar, defaultHour: Int, defaultMinute: Int, defaultBefore: Int) -> String {
        let zone = calendar.timeZone
        let offset = offsetText(zone.secondsFromGMT(for: now))
        let defaultTime = String(format: "%02d:%02d", defaultHour, defaultMinute)
        let today = dayText(now, calendar)
        let time = format(now, "HH:mm", calendar)
        let tomorrow = dayText(calendar.date(byAdding: .day, value: 1, to: now) ?? now, calendar)
        let afterTomorrow = dayText(calendar.date(byAdding: .day, value: 2, to: now) ?? now, calendar)

        // Модели плохо считают дни недели — даём готовый список на неделю вперёд.
        let days = (0...7).map { n -> String in
            let date = calendar.date(byAdding: .day, value: n, to: now) ?? now
            let label = n == 0 ? "сегодня, " : n == 1 ? "завтра, " : n == 2 ? "послезавтра, " : ""
            return "- \(label)\(dayText(date, calendar)), \(weekday(date, calendar))"
        }.joined(separator: "\n")

        return """
        Ты разбираешь сообщения для приложения заметок и напоминаний. Ответ — только json-объект, без пояснений и без ```.

        Сейчас: \(today) \(time), \(weekday(now, calendar)). Часовой пояс: \(zone.identifier) (UTC\(offset)).
        Ближайшие дни:
        \(days)

        Формат ответа:
        {"items":[{"kind":"reminder","title":"Подойти к учителю","body":null,"due":"\(tomorrow)T\(defaultTime):00\(offset)","time_given":false,"remind_before_min":\(defaultBefore),"repeat":null,"tags":["школа"]}],"reply":"Напоминание на завтра, \(defaultTime)."}

        Виды записей (kind):
        - "reminder" — дело, которое надо сделать, со сроком или без.
        - "idea" — идея, задумка, «а что если». Сообщение начинается со слова «идея» → idea.
        - "note" — сведения, которые надо запомнить: размеры, адреса, пароли, факты.

        Срок (due) бывает только у reminder, строка вида \(today)T18:00:00\(offset). У idea и note: due=null, remind_before_min=null, repeat=null.
        - Назван день без времени → \(defaultTime), time_given=false.
        - Названо время или часть дня → time_given=true. «утром» 09:00, «днём» 13:00, «после школы» 15:00, «вечером» 19:00, «перед сном» 22:00. «в 7 вечера» → 19:00, «в 8:30» → 08:30.
        - «завтра» — \(tomorrow), «послезавтра» — \(afterTomorrow).
        - День недели («в понедельник», «в пятницу») → ближайший такой день из списка «Ближайшие дни», но не сегодня: если сегодня тот же день недели — через 7 дней.
        - «через N минут», «через N часов» → сейчас плюс N, time_given=true.
        - Время без дня: если сегодня оно ещё не наступило — сегодня, если уже прошло — завтра.
        - «напомни за час» → remind_before_min=60, «за 30 минут» → 30. Не сказано → \(defaultBefore). Нет срока → null.
        - «каждый день» → repeat="daily"; «каждый вторник», «каждую неделю» → "weekly"; «каждое 5-е число», «каждый месяц» → "monthly". due — ближайший такой раз в будущем.
        - Срок не назван → due=null. Дату не выдумывай.

        title — до 6 слов, с заглавной буквы, без точки в конце. У reminder начинается с глагола: «Позвонить маме», «Написать контрольную». Без «надо», «нужно», «напомни».
        body — подробности, которые не вошли в title, иначе null.
        Несколько дел или мыслей в одном сообщении → несколько записей, по одной на каждое.
        tags — 0–2 коротких слова строчными по смыслу: школа, ресейл, сервер.
        reply — одна короткая фраза по-русски о том, что записано.
        """
    }

    static func weekday(_ date: Date, _ calendar: Calendar) -> String {
        weekdays[(calendar.component(.weekday, from: date) - 1) % 7]
    }

    static func dayText(_ date: Date, _ calendar: Calendar) -> String {
        format(date, "yyyy-MM-dd", calendar)
    }

    static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// 10800 → «+03:00».
    static func offsetText(_ seconds: Int) -> String {
        let minutes = abs(seconds) / 60
        return (seconds < 0 ? "-" : "+") + String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
