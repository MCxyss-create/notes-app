import Foundation

/// Что ищем в записи.
struct SearchFields {
    let title: String
    let body: String?
    let rawInput: String?
    let tags: [String]
    /// «Проекты / VPN»: поиск находит запись и по имени папки.
    var folderPath: String? = nil
}

/// Поиск: все слова запроса должны найтись. Слово ищется в заголовке, подробностях,
/// исходной фразе, тегах и имени папки; «#тег» — только в тегах. «ё» и «е» не различаются.
enum SearchMatcher {
    static func matches(_ fields: SearchFields, query: String) -> Bool {
        let tokens = normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return false }

        let text = normalize([fields.title, fields.body ?? "", fields.rawInput ?? "", fields.folderPath ?? ""]
            .joined(separator: " "))
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
