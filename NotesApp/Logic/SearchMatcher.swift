import Foundation

/// Что ищем в записи.
struct SearchFields {
    let title: String
    let body: String?
    let rawInput: String?
    let tags: [String]
}

/// Поиск: все слова запроса должны найтись. Слово ищется в заголовке, подробностях,
/// исходной фразе и тегах; «#тег» — только в тегах. «ё» и «е» не различаются.
enum SearchMatcher {
    static func matches(_ fields: SearchFields, query: String) -> Bool {
        let tokens = normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return false }

        let text = normalize([fields.title, fields.body ?? "", fields.rawInput ?? ""].joined(separator: " "))
        let tags = fields.tags.map(normalize)

        for token in tokens {
            if token.hasPrefix("#") {
                let tag = String(token.dropFirst())
                if tag.isEmpty { continue }
                guard tags.contains(where: { $0.hasPrefix(tag) }) else { return false }
            } else {
                guard text.contains(token) || tags.contains(where: { $0.hasPrefix(token) }) else { return false }
            }
        }
        return true
    }

    static func normalize(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "ё", with: "е")
    }
}
