import Foundation

/// Всё, что нужно ленте, чтобы разложить запись по блокам.
protocol FeedGroupable {
    var dueAt: Date? { get }
    var isDone: Bool { get }
    var doneAt: Date? { get }
    var createdAt: Date { get }
}

/// Блоки ленты в порядке показа.
enum FeedSection: String, CaseIterable, Identifiable {
    case overdue
    case today
    case tomorrow
    case later
    case noDate
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overdue: return "Просрочено"
        case .today: return "Сегодня"
        case .tomorrow: return "Завтра"
        case .later: return "Позже"
        case .noDate: return "Без срока"
        case .done: return "Выполнено"
        }
    }
}

struct FeedGroup<T>: Identifiable {
    let section: FeedSection
    let items: [T]
    var id: FeedSection { section }
}

enum FeedGrouping {
    /// Раскладывает напоминания по блокам. Пустые блоки не возвращаются.
    static func group<T: FeedGroupable>(
        _ items: [T],
        now: Date,
        calendar: Calendar = .current
    ) -> [FeedGroup<T>] {
        let startToday = calendar.startOfDay(for: now)
        let startTomorrow = calendar.date(byAdding: .day, value: 1, to: startToday) ?? startToday.addingTimeInterval(86_400)
        let startAfter = calendar.date(byAdding: .day, value: 2, to: startToday) ?? startToday.addingTimeInterval(172_800)

        var buckets: [FeedSection: [T]] = [:]
        for item in items {
            let section: FeedSection
            if item.isDone {
                section = .done
            } else if let due = item.dueAt {
                if due < now {
                    section = .overdue
                } else if due < startTomorrow {
                    section = .today
                } else if due < startAfter {
                    section = .tomorrow
                } else {
                    section = .later
                }
            } else {
                section = .noDate
            }
            buckets[section, default: []].append(item)
        }

        var result: [FeedGroup<T>] = []
        for section in FeedSection.allCases {
            guard var list = buckets[section], !list.isEmpty else { continue }
            switch section {
            case .done:
                list.sort { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
            case .noDate:
                list.sort { $0.createdAt > $1.createdAt }
            default:
                list.sort { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            }
            result.append(FeedGroup(section: section, items: list))
        }
        return result
    }
}
