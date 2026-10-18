import Foundation

/// Когда голосовая запись заканчивается сама: замолчал после слов — фраза уходит,
/// ничего не сказал — микрофон тихо выключается.
enum VoicePause {
    enum Decision: Equatable {
        case listen
        case send
        case giveUp
    }

    /// Тишина после последнего слова, после которой фраза уходит.
    static let pause: TimeInterval = 1.6
    /// Слова не меняются так долго — отправляем, даже если вокруг шумно.
    static let stuck: TimeInterval = 4
    /// Ничего не сказали за столько — выключаемся.
    static let silence: TimeInterval = 8
    /// Самая длинная запись (распознавание Apple — до минуты).
    static let longest: TimeInterval = 55
    /// Громче этого — человек говорит или тянет «эээ»: не перебиваем.
    static let loudLevel: Float = 0.35

    static func decide(now: Date, started: Date, lastChange: Date, lastLoud: Date, hasText: Bool) -> Decision {
        let elapsed = now.timeIntervalSince(started)
        let sinceSound = now.timeIntervalSince(lastLoud)
        guard hasText else {
            if elapsed >= longest { return .giveUp }
            return elapsed >= silence && sinceSound >= 2 ? .giveUp : .listen
        }
        if elapsed >= longest { return .send }
        let sinceWords = now.timeIntervalSince(lastChange)
        if sinceWords >= stuck { return .send }
        if sinceWords >= pause && sinceSound >= 1 { return .send }
        return .listen
    }

    /// Громкость 0…1 из среднего уровня сигнала: −50 дБ и тише — 0, −10 дБ и громче — 1.
    static func level(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return min(1, max(0, (db + 50) / 40))
    }
}
