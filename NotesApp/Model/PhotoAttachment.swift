import Foundation
import SwiftData

/// Фото к записи. Хранится только на телефоне и в резервной копии, в DeepSeek не уходит.
/// Связь с записью — через itemID, без @Relationship.
@Model
final class PhotoAttachment {
    @Attribute(.unique) var uid: UUID = UUID()
    var itemID: UUID = UUID()
    var createdAt: Date = Date()
    var sortIndex: Int = 0
    /// JPEG, длинная сторона не больше 2048 px. Лежит отдельным файлом, а не в самой базе.
    @Attribute(.externalStorage) var imageData: Data = Data()
    /// Миниатюра 300 px — для списков и сеток.
    var thumbData: Data = Data()
    /// Размер imageData: чтобы посчитать вес копии, не читая все фото.
    var byteCount: Int = 0

    init(itemID: UUID, imageData: Data, thumbData: Data, sortIndex: Int, createdAt: Date = Date()) {
        self.uid = UUID()
        self.itemID = itemID
        self.imageData = imageData
        self.thumbData = thumbData
        self.byteCount = imageData.count
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}
