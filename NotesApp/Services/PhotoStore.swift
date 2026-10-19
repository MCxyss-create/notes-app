import Foundation
import ImageIO
import SwiftData
import UIKit

/// Фото, готовое к сохранению: уже уменьшено, с миниатюрой. Ещё не прикреплено к записи.
struct PreparedPhoto: Identifiable, Equatable {
    let id = UUID()
    let image: Data
    let thumb: Data
}

/// Фото записей: подготовка (поворот, уменьшение, JPEG), прикрепление до 10 штук, удаление
/// вместе с записью и уборка «сирот».
@MainActor
enum PhotoStore {
    // MARK: - Подготовка (можно звать не с главного потока)

    /// Из файла (галерея): поворот по EXIF, длинная сторона до 2048 px, JPEG 0.8, миниатюра 300 px.
    nonisolated static func prepare(data: Data) -> PreparedPhoto? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = downscaled(source, maxSide: PhotoMath.maxSide),
              let thumb = downscaled(source, maxSide: PhotoMath.thumbSide),
              let imageJPEG = UIImage(cgImage: image).jpegData(compressionQuality: PhotoMath.quality),
              let thumbJPEG = UIImage(cgImage: thumb).jpegData(compressionQuality: PhotoMath.thumbQuality)
        else { return nil }
        return PreparedPhoto(image: imageJPEG, thumb: thumbJPEG)
    }

    /// С камеры: рисуем заново — фото встаёт прямо (ориентация учтена) и сразу уменьшается.
    nonisolated static func prepare(image: UIImage) -> PreparedPhoto? {
        guard let big = render(image, maxSide: PhotoMath.maxSide).jpegData(compressionQuality: PhotoMath.quality),
              let small = render(image, maxSide: PhotoMath.thumbSide).jpegData(compressionQuality: PhotoMath.thumbQuality)
        else { return nil }
        return PreparedPhoto(image: big, thumb: small)
    }

    /// Миниатюра из сохранённого фото — для восстановления из копии.
    nonisolated static func thumb(from imageData: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let thumb = downscaled(source, maxSide: PhotoMath.thumbSide) else { return nil }
        return UIImage(cgImage: thumb).jpegData(compressionQuality: PhotoMath.thumbQuality)
    }

    nonisolated private static func downscaled(_ source: CGImageSource, maxSide: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Поворот по EXIF: фото с телефона не ляжет боком.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxSide),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    nonisolated private static func render(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let size = PhotoMath.fitted(pixels, maxSide: maxSide)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - База

    static func photos(of itemID: UUID, context: ModelContext) -> [PhotoAttachment] {
        let descriptor = FetchDescriptor<PhotoAttachment>(predicate: #Predicate<PhotoAttachment> { $0.itemID == itemID },
                                                          sortBy: [SortDescriptor(\.sortIndex)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Прикрепляет фото к записи — не больше 10 на запись. Возвращает, сколько прикрепилось.
    @discardableResult
    static func add(_ prepared: [PreparedPhoto], to itemID: UUID, context: ModelContext, now: Date = Date()) -> Int {
        let existing = photos(of: itemID, context: context)
        let accepted = prepared.prefix(PhotoMath.remaining(current: existing.count))
        let next = (existing.map(\.sortIndex).max() ?? -1) + 1
        for (offset, photo) in accepted.enumerated() {
            context.insert(PhotoAttachment(itemID: itemID, imageData: photo.image, thumbData: photo.thumb,
                                           sortIndex: next + offset, createdAt: now))
        }
        try? context.save()
        return accepted.count
    }

    static func delete(_ photo: PhotoAttachment, context: ModelContext) {
        context.delete(photo)
        try? context.save()
    }

    /// Удаляет запись вместе с её фото.
    static func deleteItem(_ item: Item, context: ModelContext) {
        for photo in photos(of: item.uid, context: context) {
            context.delete(photo)
        }
        context.delete(item)
    }

    /// Фото без записи — убираем при запуске. Возвращает, сколько убрали.
    @discardableResult
    static func removeOrphans(context: ModelContext) -> Int {
        let items = Set(((try? context.fetch(FetchDescriptor<Item>())) ?? []).map(\.uid))
        var descriptor = FetchDescriptor<PhotoAttachment>()
        descriptor.propertiesToFetch = [\.uid, \.itemID]
        let orphans = ((try? context.fetch(descriptor)) ?? []).filter { !items.contains($0.itemID) }
        for photo in orphans {
            context.delete(photo)
        }
        if !orphans.isEmpty {
            try? context.save()
        }
        return orphans.count
    }

    /// Сколько всего фото и сколько они весят — для строки в «Резервной копии».
    static func stats(context: ModelContext) -> (count: Int, bytes: Int) {
        var descriptor = FetchDescriptor<PhotoAttachment>()
        descriptor.propertiesToFetch = [\.byteCount]
        let all = (try? context.fetch(descriptor)) ?? []
        return (all.count, all.reduce(0) { $0 + $1.byteCount })
    }
}
