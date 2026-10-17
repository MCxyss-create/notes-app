import Foundation
import SwiftData

/// Фраза для ИИ, которую не удалось разобрать сразу: не было сети или ключа, DeepSeek не ответил.
/// Лежит во «Входящих», пока её не разберут и не сохранят.
@Model
final class InboxEntry {
    @Attribute(.unique) var uid: UUID = UUID()
    var text: String = ""
    /// Когда фраза сказана: от этого момента ИИ считает «завтра» и «через час».
    var createdAt: Date = Date()
    /// Ответ ИИ (JSON), ждёт подтверждения на карточках.
    var parsedJSON: String?
    /// Ошибка, из-за которой фраза не разобралась сама. nil — просто ждёт сети.
    var lastError: String?

    init(text: String, createdAt: Date = Date()) {
        self.uid = UUID()
        self.text = text
        self.createdAt = createdAt
    }
}
