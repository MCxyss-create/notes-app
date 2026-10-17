import Foundation

/// Теги, которые пишет человек: «Школа, #сервер ,  ресейл» → ["школа", "сервер", "ресейл"].
enum TagText {
    static let maxCount = 10
    static let maxLength = 30

    static func parse(_ text: String) -> [String] {
        let junk = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "#"))
        var result: [String] = []
        for piece in text.components(separatedBy: CharacterSet(charactersIn: ",;")) {
            let tag = piece.trimmingCharacters(in: junk).lowercased()
            guard !tag.isEmpty, tag.count <= maxLength, !result.contains(tag) else { continue }
            result.append(tag)
            if result.count == maxCount { break }
        }
        return result
    }

    /// «#школа #сервер».
    static func display(_ tags: [String]) -> String {
        tags.map { "#\($0)" }.joined(separator: " ")
    }
}
