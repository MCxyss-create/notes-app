import SwiftData
import UIKit
import XCTest
@testable import NotesApp

/// Фото: размеры при уменьшении, лимит 10, удаление вместе с записью, «сироты», резервная копия.
final class PhotoTests: XCTestCase {
    private var container: ModelContainer?

    /// База в памяти; контейнер держим, пока идёт тест.
    @MainActor
    private func memoryContext() throws -> ModelContext {
        let made = try ModelContainer(for: Item.self, InboxEntry.self, Folder.self, PhotoAttachment.self,
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        container = made
        return made.mainContext
    }

    private func fake(_ n: Int) -> [PreparedPhoto] {
        (0..<n).map { PreparedPhoto(image: Data([UInt8($0), 1, 2, 3]), thumb: Data([UInt8($0)])) }
    }

    func testFittedSizes() {
        // Фото с камеры 4032×3024 → 2048×1536; вертикальное — так же, но стоя.
        XCTAssertEqual(PhotoMath.fitted(CGSize(width: 4032, height: 3024), maxSide: 2048), CGSize(width: 2048, height: 1536))
        XCTAssertEqual(PhotoMath.fitted(CGSize(width: 3024, height: 4032), maxSide: 2048), CGSize(width: 1536, height: 2048))
        // Маленькое не растягиваем.
        XCTAssertEqual(PhotoMath.fitted(CGSize(width: 1000, height: 800), maxSide: 2048), CGSize(width: 1000, height: 800))
        // Миниатюра 300 и очень узкая картинка — не меньше 1 px.
        XCTAssertEqual(PhotoMath.fitted(CGSize(width: 4032, height: 3024), maxSide: PhotoMath.thumbSide),
                       CGSize(width: 300, height: 225))
        XCTAssertEqual(PhotoMath.fitted(CGSize(width: 10000, height: 1), maxSide: 300), CGSize(width: 300, height: 1))
        XCTAssertEqual(PhotoMath.fitted(.zero, maxSide: 300), .zero)
    }

    func testLimitAndTexts() {
        XCTAssertEqual(PhotoMath.limit, 10)
        XCTAssertEqual(PhotoMath.remaining(current: 3), 7)
        XCTAssertEqual(PhotoMath.remaining(current: 12), 0)
        XCTAssertEqual(PhotoMath.counterText(3), "3 из 10")
        XCTAssertEqual(PhotoMath.sizeText(bytes: 41 * 1_048_576), "41 МБ")
        XCTAssertEqual(PhotoMath.sizeText(bytes: 1_572_864), "1,5 МБ")
        XCTAssertEqual(PhotoMath.sizeText(bytes: 820 * 1024), "820 КБ")
    }

    /// Настоящая картинка: уменьшается до 2048, миниатюра — до 300, и обе — JPEG.
    func testPrepareShrinksAndMakesThumb() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let big = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1500), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1500))
        }
        let photo = try XCTUnwrap(PhotoStore.prepare(image: big))
        let image = try XCTUnwrap(UIImage(data: photo.image))
        let thumb = try XCTUnwrap(UIImage(data: photo.thumb))
        XCTAssertEqual(image.size.width * image.scale, 2048)
        XCTAssertEqual(image.size.height * image.scale, 1024)
        XCTAssertEqual(max(thumb.size.width, thumb.size.height) * thumb.scale, 300)

        let fromFile = try XCTUnwrap(PhotoStore.prepare(data: try XCTUnwrap(big.jpegData(compressionQuality: 0.9))))
        let restored = try XCTUnwrap(UIImage(data: fromFile.image))
        XCTAssertEqual(max(restored.size.width, restored.size.height) * restored.scale, 2048)
    }

    /// Больше 10 на запись не прикрепляется, порядок сохраняется.
    @MainActor
    func testNoMoreThanTenPerItem() throws {
        let context = try memoryContext()
        let item = Item(kind: .idea, title: "Бот")
        context.insert(item)

        XCTAssertEqual(PhotoStore.add(fake(7), to: item.uid, context: context), 7)
        XCTAssertEqual(PhotoStore.add(fake(5), to: item.uid, context: context), 3)
        XCTAssertEqual(PhotoStore.add(fake(1), to: item.uid, context: context), 0)
        let photos = PhotoStore.photos(of: item.uid, context: context)
        XCTAssertEqual(photos.count, 10)
        XCTAssertEqual(photos.map(\.sortIndex), Array(0..<10))
        XCTAssertEqual(photos[0].byteCount, 4)
    }

    /// Удалили запись — её фото тоже; чужие фото на месте. «Сироты» убираются.
    @MainActor
    func testDeletingItemDeletesPhotosAndOrphansAreRemoved() throws {
        let context = try memoryContext()
        let gone = Item(kind: .note, title: "Удалю")
        let kept = Item(kind: .reminder, title: "Оставлю")
        context.insert(gone)
        context.insert(kept)
        PhotoStore.add(fake(3), to: gone.uid, context: context)
        PhotoStore.add(fake(2), to: kept.uid, context: context)

        PhotoStore.deleteItem(gone, context: context)
        try context.save()
        XCTAssertTrue(PhotoStore.photos(of: gone.uid, context: context).isEmpty)
        XCTAssertEqual(PhotoStore.photos(of: kept.uid, context: context).count, 2)

        context.insert(PhotoAttachment(itemID: UUID(), imageData: Data([1]), thumbData: Data([1]), sortIndex: 0))
        try context.save()
        XCTAssertEqual(PhotoStore.removeOrphans(context: context), 1)
        XCTAssertEqual(PhotoStore.stats(context: context).count, 2)
    }

    /// Копия с фото туда-обратно; при восстановлении — без дублей и только к своим записям.
    func testBackupWithPhotosRoundTrip() throws {
        let itemID = UUID()
        let photo = BackupPhoto(uid: UUID(), itemID: itemID, createdAt: TestCalendar.date("2026-10-18 10:00"),
                                sortIndex: 0, data: Data([0xFF, 0xD8, 0xFF, 0x00]))
        let stray = BackupPhoto(uid: UUID(), itemID: UUID(), createdAt: TestCalendar.date("2026-10-18 10:01"),
                                sortIndex: 0, data: Data([1]))
        let file = try Backup.decode(Backup.encode([], photos: [photo, stray, photo],
                                                   exportedAt: TestCalendar.date("2026-10-18 12:00")))
        XCTAssertEqual(file.version, Backup.version)
        XCTAssertEqual(file.photos, [photo, stray, photo])

        let fresh = Backup.newPhotos(in: file, existing: [], existingItems: [itemID])
        XCTAssertEqual(fresh, [photo])
        XCTAssertEqual(Backup.newPhotos(in: file, existing: [photo.uid], existingItems: [itemID]), [])
    }

    /// Копия версии 2 (с папками, без фото) читается как раньше.
    func testOldBackupWithoutPhotos() throws {
        let json = """
        {"app":"Мысли","version":2,"exportedAt":"2026-10-18T09:00:00Z","items":[],"folders":[]}
        """
        let file = try Backup.decode(Data(json.utf8))
        XCTAssertEqual(file.version, 2)
        XCTAssertNil(file.photos)
        XCTAssertEqual(Backup.newPhotos(in: file, existing: [], existingItems: []), [])
    }
}
