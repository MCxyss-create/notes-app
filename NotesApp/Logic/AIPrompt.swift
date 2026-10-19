import Foundation

/// Системный промт для DeepSeek: правила разбора, текущие дата и время, день недели, часовой пояс.
enum AIPrompt {
    static let weekdays = ["воскресенье", "понедельник", "вторник", "среда", "четверг", "пятница", "суббота"]

    /// known — записи, которые уже есть (уже отобранные `AIContext.forPrompt`): по ним ИИ понимает команды.
    /// folders — папки для идей и заметок: ИИ раскладывает по ним сам.
    static func system(now: Date, calendar: Calendar, defaultHour: Int, defaultMinute: Int, defaultBefore: Int,
                       known: [AIKnownItem] = [], folders: [AIKnownFolder] = []) -> String {
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

        let base = """
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

        Сообщение часто надиктовано голосом: без знаков препинания, со словами-паразитами (ну, короче, типа, как бы, э-э, вот, это самое) и ошибками распознавания. Слова-паразиты убирай, очевидные ошибки исправляй по смыслу, знаки расставляй. В title и body — чистый текст, а не сырая речь.
        """
        let filed = base + "\n\n" + folderRules(folders) + "\n\n" + eventRules
        guard !known.isEmpty else { return filed }
        return filed + "\n\n" + commands(known, now: now, calendar: calendar, offset: offset, defaultTime: defaultTime)
    }

    /// Дни рождения, годовщины и другие ежегодные даты — в календарь, а не в дела.
    static let eventRules = """
    Дни рождения, годовщины и другие даты, которые повторяются каждый год («каждый год 5 июня»), — не reminder, а "events":
    {"items":[],"events":[{"type":"birthday","title":"Лёша","date":"--03-12","year":null,"remind_days":[0,1]}],"reply":"Добавил день рождения Лёши — 12 марта."}
    - type: "birthday" — день рождения (title — имя, как сказано: «Лёша», «мама»), "anniversary" — годовщина (title — что за годовщина: «Годовщина свадьбы родителей»), "other" — другая ежегодная дата.
    - date: без года — "--ММ-ДД", с годом — "ГГГГ-ММ-ДД". year — год рождения или события, если назван, иначе null.
    - remind_days: за сколько дней напомнить: 0 — в день, 1 — за день, 3, 7 — за неделю. Не сказано — [0,1].
    Обычное дело с датой — это items с kind "reminder", не events.
    """

    /// Список папок и когда класть в них идеи и заметки.
    static func folderRules(_ folders: [AIKnownFolder]) -> String {
        let list = folders.isEmpty
            ? "Папок пока нет."
            : "Папки для идей и заметок (id | путь):\n" + folders.map { "- \($0.ref) | \($0.path)" }.joined(separator: "\n")
        return """
        \(list)

        У idea и note можно указать "folder" — id папки из списка, только если по смыслу ясно, куда: «идея для VPN: …», «в папку школа», «для проекта VPN». Не уверен — "folder": null. У reminder "folder" всегда null.
        Новую папку не создавай. Только если прямо сказано «создай папку X» или «в новую папку X» — "folder_new": "X", а "folder": null.
        """
    }

    /// Список записей и правила команд: «перенеси», «готово», «удали», «переименуй», «что у меня…».
    static func commands(_ known: [AIKnownItem], now: Date, calendar: Calendar, offset: String, defaultTime: String) -> String {
        let list = known.map { AIContext.line($0, calendar: calendar) }.joined(separator: "\n")
        let example = known.first?.ref ?? "a1b2c3"
        let later = dayText(calendar.date(byAdding: .day, value: 3, to: now) ?? now, calendar)
        return """
        Записи, которые уже есть (id | вид | заголовок | срок | повтор):
        \(list)

        Сообщение может быть командой про запись из этого списка. Тогда новую запись НЕ создавай, а добавь изменение в "changes" (id — из списка):
        - сделано («готово», «сделал», «маме позвонил») → {"op":"done","id":"\(example)"}
        - перенести («перенеси на пятницу», «сдвинь на час», «отложи на завтра») → {"op":"move","id":"\(example)","due":"\(later)T\(defaultTime):00\(offset)","time_given":true}. Назван только день — оставь прежнее время записи. «Сдвинь на час» — от прежнего срока.
        - удалить («удали», «убери», «больше не надо») → {"op":"delete","id":"\(example)"}
        - переименовать или дописать → {"op":"edit","id":"\(example)","title":"…","body":"…"} — только то, что меняется.
        - переложить идею или заметку в папку («перенеси идею про бота в папку VPN») → {"op":"folder","id":"\(example)","folder":"<id папки из списка>"}.
        Вопрос про записи («что у меня завтра?», «что просрочено?», «какие идеи?») → "found": id подходящих записей по порядку, items и changes пустые, reply — короткий ответ по-русски.
        Не уверен, о какой записи речь, — ничего не меняй и спроси в reply.
        В одном сообщении могут быть и новые записи, и команды — тогда заполни и items, и changes.
        Ответ с командой: {"items":[],"changes":[{"op":"done","id":"\(example)"}],"reply":"Отметил как сделанное."}
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
