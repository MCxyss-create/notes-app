import Foundation

/// Варианты «отложить» в свайпе влево.
enum SnoozeOption {
    case hour
    case evening
    case tomorrow
}

enum DateMath {
    static let eveningHour = 19

    /// Тот же день, но в указанное время (секунды = 0).
    static func atTime(_ day: Date, hour: Int, minute: Int, calendar: Calendar = .current) -> Date {
        var c = calendar.dateComponents([.year, .month, .day], from: day)
        c.hour = hour
        c.minute = minute
        c.second = 0
        return calendar.date(from: c) ?? day
    }

    /// Через час, без секунд.
    static func inOneHour(from now: Date, calendar: Calendar = .current) -> Date {
        let later = now.addingTimeInterval(3600)
        var c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: later)
        c.second = 0
        return calendar.date(from: c) ?? later
    }

    /// Сегодня в 19:00, а если уже позже — завтра в 19:00.
    static func evening(from now: Date, calendar: Calendar = .current) -> Date {
        let today = atTime(now, hour: eveningHour, minute: 0, calendar: calendar)
        if today > now { return today }
        let nextDay = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
        return atTime(nextDay, hour: eveningHour, minute: 0, calendar: calendar)
    }

    /// Завтра в указанное время.
    static func tomorrow(hour: Int, minute: Int, from now: Date, calendar: Calendar = .current) -> Date {
        let nextDay = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
        return atTime(nextDay, hour: hour, minute: minute, calendar: calendar)
    }

    /// Новая дата для «отложить».
    /// «Завтра» сохраняет время напоминания, если оно было указано, иначе — время по умолчанию.
    static func snooze(
        _ option: SnoozeOption,
        due: Date?,
        timeGiven: Bool,
        defaultHour: Int,
        defaultMinute: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> Date {
        switch option {
        case .hour:
            return inOneHour(from: now, calendar: calendar)
        case .evening:
            return evening(from: now, calendar: calendar)
        case .tomorrow:
            if let due, timeGiven {
                let h = calendar.component(.hour, from: due)
                let m = calendar.component(.minute, from: due)
                return tomorrow(hour: h, minute: m, from: now, calendar: calendar)
            }
            return tomorrow(hour: defaultHour, minute: defaultMinute, from: now, calendar: calendar)
        }
    }
}
