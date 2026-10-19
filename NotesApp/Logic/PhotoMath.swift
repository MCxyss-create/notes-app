import CoreGraphics
import Foundation

/// Размеры фото и лимит на запись. Без UIKit — для тестов.
enum PhotoMath {
    /// Не больше 10 фото на запись.
    static let limit = 10
    /// Длинная сторона сохранённого фото, px.
    static let maxSide: CGFloat = 2048
    /// Длинная сторона миниатюры, px.
    static let thumbSide: CGFloat = 300
    static let quality: CGFloat = 0.8
    static let thumbQuality: CGFloat = 0.7

    /// Размер после уменьшения: длинная сторона не больше maxSide, пропорции те же, маленькое не растягиваем.
    static func fitted(_ size: CGSize, maxSide: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let long = max(size.width, size.height)
        guard long > maxSide else { return CGSize(width: size.width.rounded(), height: size.height.rounded()) }
        let scale = maxSide / long
        return CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
    }

    /// Сколько ещё можно добавить к записи, где уже current фото.
    static func remaining(current: Int) -> Int {
        max(0, limit - current)
    }

    /// «3 из 10».
    static func counterText(_ count: Int) -> String {
        "\(min(count, limit)) из \(limit)"
    }

    /// «41 МБ», «820 КБ».
    static func sizeText(bytes: Int) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 {
            return mb >= 10 ? "\(Int(mb.rounded())) МБ" : String(format: "%.1f МБ", mb).replacingOccurrences(of: ".", with: ",")
        }
        return "\(Int((Double(bytes) / 1024).rounded())) КБ"
    }
}
