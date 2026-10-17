import Foundation

/// Куда и с чем ходить в DeepSeek.
struct AIConfig {
    static let defaultEndpoint = "https://api.deepseek.com/chat/completions"
    static let defaultModel = "deepseek-flash"

    let endpoint: URL
    let model: String
    let apiKey: String

    /// Адрес из настроек: пусто — по умолчанию; «https://api.deepseek.com» → «…/chat/completions».
    static func url(from text: String) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { value = defaultEndpoint }
        if !value.contains("://") { value = "https://" + value }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        if !value.hasSuffix("/chat/completions") { value += "/chat/completions" }
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host != nil else { return nil }
        return url
    }
}

/// Почему ИИ не разобрал фразу. Фраза при этом не теряется — уходит во «Входящие».
enum AIError: Error, Equatable {
    case noKey
    case badEndpoint
    case offline
    case http(Int, String?)
    case badResponse(String)
    case failed(String)

    /// Пройдёт само: нет сети, DeepSeek перегружен. Такие фразы разбираются повторно без кнопки.
    var isTemporary: Bool {
        switch self {
        case .offline: return true
        case .http(let code, _): return code == 429 || code >= 500
        default: return false
        }
    }

    var message: String {
        switch self {
        case .noKey:
            return "Нет ключа DeepSeek — добавь его в настройках"
        case .badEndpoint:
            return "Неверный адрес DeepSeek в настройках"
        case .offline:
            return "Нет сети"
        case .http(let code, let text):
            let base: String
            switch code {
            case 401: base = "Ключ DeepSeek не подошёл"
            case 402: base = "На балансе DeepSeek закончились деньги"
            case 400, 404, 422: base = "DeepSeek не принял запрос"
            case 429: base = "DeepSeek просит подождать"
            case 500...599: base = "DeepSeek сейчас не отвечает"
            default: base = "Ошибка DeepSeek"
            }
            // Для «не принял запрос» причина важна: например, неверное имя модели.
            if let text, !text.isEmpty, [400, 404, 422].contains(code) {
                return "\(base) (\(code)): \(text)"
            }
            return "\(base) (\(code))"
        case .badResponse(let why):
            return "ИИ ответил непонятно: \(why)"
        case .failed(let why):
            return "Не получилось связаться с DeepSeek: \(why)"
        }
    }

    static func from(_ error: Error) -> AIError {
        if let known = error as? AIError { return known }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed,
                 .callIsActive, .secureConnectionFailed:
                return .offline
            default:
                return .failed(urlError.localizedDescription)
            }
        }
        return .failed(error.localizedDescription)
    }
}

/// Запрос к DeepSeek в формате OpenAI: без «размышлений», ответ — JSON.
enum DeepSeekClient {
    static func makeRequest(config: AIConfig, system: String, phrase: String) throws -> URLRequest {
        var request = URLRequest(url: config.endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": config.model,
            "thinking": ["type": "disabled"],
            "response_format": ["type": "json_object"],
            "stream": false,
            "max_tokens": 2000,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": phrase],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Текст ответа модели: `choices[0].message.content`.
    static func content(from data: Data) throws -> String {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.badResponse("пустой ответ")
        }
        return content
    }

    /// Причина ошибки из ответа: `{"error":{"message":"…"}}`.
    static func errorMessage(from data: Data) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let error = root["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }

    static func send(config: AIConfig, system: String, phrase: String, session: URLSession = .shared) async throws -> String {
        let request = try makeRequest(config: config, system: system, phrase: phrase)
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            throw AIError.from(error)
        }
        let (data, response) = result
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AIError.http(status, errorMessage(from: data))
        }
        return try content(from: data)
    }
}
