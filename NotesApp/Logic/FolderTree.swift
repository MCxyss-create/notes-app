import Foundation

/// Папка без SwiftData — для правил и тестов.
struct FolderNode: Identifiable, Equatable {
    let id: UUID
    var name: String
    var parentID: UUID?
    var sortIndex: Int = 0
    var createdAt: Date = .distantPast
}

/// Строка дерева для выбора папки: папка и её уровень (0 — верхний).
struct FolderLine: Identifiable, Equatable {
    let node: FolderNode
    let level: Int
    var id: UUID { node.id }
}

/// Правила папок: не глубже 3 уровней, имя уникально среди соседей («ё» = «е», без учёта регистра),
/// папку нельзя положить в саму себя или в свою подпапку, путь — «Проекты / VPN / Реклама».
/// Удалённая папка отдаёт записи и подпапки своему родителю.
enum FolderTree {
    static let maxDepth = 3
    static let separator = " / "

    /// Родитель папки. Родителя нет в базе или папки замкнулись в круг — папка считается верхней.
    static func parent(of node: FolderNode, in nodes: [FolderNode]) -> UUID? {
        guard let start = node.parentID, start != node.id else { return nil }
        var seen: Set<UUID> = [node.id]
        var current: UUID? = start
        while let id = current {
            guard let found = nodes.first(where: { $0.id == id }) else { return id == start ? nil : start }
            if seen.contains(id) { return nil }
            seen.insert(id)
            current = found.parentID
        }
        return start
    }

    /// Папки одного уровня (nil — верхний): по порядку, потом по имени.
    static func children(of parent: UUID?, in nodes: [FolderNode]) -> [FolderNode] {
        nodes
            .filter { $0.id != parent && self.parent(of: $0, in: nodes) == parent }
            .sorted { a, b in
                if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }

    /// Путь от верхнего уровня до папки включительно.
    static func path(to id: UUID, in nodes: [FolderNode]) -> [FolderNode] {
        var result: [FolderNode] = []
        var current = nodes.first { $0.id == id }
        while let node = current, !result.contains(where: { $0.id == node.id }) {
            result.insert(node, at: 0)
            current = parent(of: node, in: nodes).flatMap { up in nodes.first { $0.id == up } }
        }
        return result
    }

    /// «Проекты / VPN / Реклама». Папки нет — пусто.
    static func pathText(_ id: UUID, in nodes: [FolderNode]) -> String {
        path(to: id, in: nodes).map(\.name).joined(separator: separator)
    }

    /// 1 — верхний уровень, 0 — «Без папки» или папки нет.
    static func depth(of id: UUID?, in nodes: [FolderNode]) -> Int {
        guard let id else { return 0 }
        return path(to: id, in: nodes).count
    }

    /// Все вложенные папки (сама папка не входит).
    static func descendants(of id: UUID, in nodes: [FolderNode]) -> Set<UUID> {
        var result: Set<UUID> = []
        var queue = [id]
        while let current = queue.popLast() {
            for child in children(of: current, in: nodes) where child.id != id && !result.contains(child.id) {
                result.insert(child.id)
                queue.append(child.id)
            }
        }
        return result
    }

    /// Сколько уровней занимает папка вместе с вложенными: 1 — без подпапок.
    static func height(of id: UUID, in nodes: [FolderNode]) -> Int {
        var best = 1
        var stack = [(id: id, level: 1)]
        var seen: Set<UUID> = [id]
        while let entry = stack.popLast() {
            best = max(best, entry.level)
            for child in children(of: entry.id, in: nodes) where !seen.contains(child.id) {
                seen.insert(child.id)
                stack.append((child.id, entry.level + 1))
            }
        }
        return best
    }

    /// Можно ли создать папку внутри parent (nil — на верхнем уровне).
    static func canCreate(in parent: UUID?, nodes: [FolderNode]) -> Bool {
        depth(of: parent, in: nodes) < maxDepth
    }

    /// Можно ли переложить папку в parent: не в себя, не в свою подпапку и не глубже 3 уровней.
    static func canMove(_ id: UUID, to parent: UUID?, in nodes: [FolderNode]) -> Bool {
        if let parent {
            guard parent != id, !descendants(of: id, in: nodes).contains(parent),
                  nodes.contains(where: { $0.id == parent }) else { return false }
        }
        return depth(of: parent, in: nodes) + height(of: id, in: nodes) <= maxDepth
    }

    /// Всё дерево по порядку, с уровнями — для выбора папки с отступами.
    static func lines(_ nodes: [FolderNode]) -> [FolderLine] {
        var result: [FolderLine] = []
        var seen: Set<UUID> = []
        func walk(_ parent: UUID?, level: Int) {
            for node in children(of: parent, in: nodes) where !seen.contains(node.id) {
                seen.insert(node.id)
                result.append(FolderLine(node: node, level: level))
                walk(node.id, level: level + 1)
            }
        }
        walk(nil, level: 0)
        return result
    }

    static func normalize(_ name: String) -> String {
        SearchMatcher.normalize(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Есть ли у соседей папка с таким именем. excluding — сама переименовываемая папка.
    static func isNameTaken(_ name: String, in parent: UUID?, excluding id: UUID? = nil, nodes: [FolderNode]) -> Bool {
        let key = normalize(name)
        return children(of: parent, in: nodes).contains { $0.id != id && normalize($0.name) == key }
    }

    /// Имя занято — «VPN 2», «VPN 3»…
    static func uniqueName(_ name: String, in parent: UUID?, excluding id: UUID? = nil, nodes: [FolderNode]) -> String {
        let taken = children(of: parent, in: nodes).filter { $0.id != id }.map { normalize($0.name) }
        return freeName(name, taken: taken)
    }

    /// Что станет при удалении папки: куда уедут записи и подпапки (родитель; nil — «Без папки»
    /// и верхний уровень) и с какими именами подпапки встанут к новым соседям.
    struct Removal: Equatable {
        let target: UUID?
        let renamed: [UUID: String]
    }

    static func removal(of id: UUID, in nodes: [FolderNode]) -> Removal {
        guard let node = nodes.first(where: { $0.id == id }) else { return Removal(target: nil, renamed: [:]) }
        let target = parent(of: node, in: nodes)
        var taken = children(of: target, in: nodes).filter { $0.id != id }.map { normalize($0.name) }
        var renamed: [UUID: String] = [:]
        for child in children(of: id, in: nodes) {
            let name = freeName(child.name, taken: taken)
            taken.append(normalize(name))
            renamed[child.id] = name
        }
        return Removal(target: target, renamed: renamed)
    }

    /// Сколько записей в папке вместе с вложенными. folderIDs — папки записей.
    static func count(in id: UUID, folderIDs: [UUID?], nodes: [FolderNode]) -> Int {
        let ids = descendants(of: id, in: nodes).union([id])
        return folderIDs.filter { folder in folder.map { ids.contains($0) } ?? false }.count
    }

    /// Запись «Без папки»: папка не задана или её уже нет.
    static func isLoose(_ folderID: UUID?, in nodes: [FolderNode]) -> Bool {
        guard let folderID else { return true }
        return !nodes.contains { $0.id == folderID }
    }

    private static func freeName(_ name: String, taken: [String]) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidate = base
        var number = 2
        while taken.contains(normalize(candidate)) {
            candidate = "\(base) \(number)"
            number += 1
        }
        return candidate
    }
}
