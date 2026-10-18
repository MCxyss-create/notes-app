import Foundation
import AVFoundation
import Speech

/// Своя кнопка микрофона: русская речь → текст в поле ввода.
/// С stopsOnPause запись заканчивается сама, когда человек замолчал (как в VoiceOS).
@MainActor
final class Dictation: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    @Published var error: String?
    /// Громкость с микрофона 0…1 — для полосок «Слушаю».
    @Published private(set) var level: Float = 0
    /// +1, когда запись закончилась сама после паузы и текст готов — поле ввода отправляет фразу.
    @Published private(set) var pauseCount = 0

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let engine = AVAudioEngine()
    private let meter = LevelMeter()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Номер записи: запоздалые ответы распознавания от прошлой записи ничего не трогают.
    private var session = 0
    private var starting = false
    private var stoppedByPause = false
    private var watcher: Task<Void, Never>?
    private var startedAt = Date()
    private var lastChange = Date()
    private var lastLoud = Date()

    func start(stopsOnPause: Bool = false) async {
        guard !isRecording, !starting else { return }
        starting = true
        defer { starting = false }
        error = nil
        guard await Self.requestAccess() else {
            error = "Нет доступа к микрофону или распознаванию речи — разреши в настройках iPhone"
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            error = "Распознавание речи сейчас недоступно"
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                error = "Микрофон не найден"
                finish()
                return
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            self.request = request

            let meter = self.meter
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                if let value = meter.feed(buffer) {
                    Task { @MainActor in self?.heard(value) }
                }
            }
            engine.prepare()
            try engine.start()

            self.session += 1
            let current = self.session
            let now = Date()
            startedAt = now
            lastChange = now
            lastLoud = now
            stoppedByPause = false
            level = 0
            transcript = ""
            isRecording = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                let text = result?.bestTranscription.formattedString
                let ended = (result?.isFinal ?? false) || failure != nil
                Task { @MainActor in
                    guard let self, self.session == current else { return }
                    if let text, text != self.transcript {
                        self.transcript = text
                        self.lastChange = Date()
                    }
                    if ended { self.finish() }
                }
            }
            if stopsOnPause {
                watchPauses(current)
            }
        } catch {
            self.error = "Не удалось включить микрофон"
            finish()
        }
    }

    /// «Стоп»: дослушиваем последние слова, через полторы секунды закрываем всё сами.
    /// send — потом отправить фразу, как после паузы.
    func stop(send: Bool = false) {
        guard isRecording else { return }
        if send {
            stoppedByPause = true
        }
        watcher?.cancel()
        watcher = nil
        request?.endAudio()
        stopEngine()
        isRecording = false
        level = 0
        let current = session
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, self.session == current else { return }
            self.finish()
        }
    }

    /// «Отмена»: выключить микрофон и ничего не отправлять.
    func cancel() {
        stoppedByPause = false
        finish()
    }

    private func finish() {
        watcher?.cancel()
        watcher = nil
        stopEngine()
        request?.endAudio()
        request = nil
        task?.finish()
        task = nil
        isRecording = false
        level = 0
        session += 1
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if stoppedByPause {
            stoppedByPause = false
            pauseCount += 1
        }
    }

    /// Раз в четверть секунды: замолчал ли человек.
    private func watchPauses(_ current: Int) {
        watcher?.cancel()
        watcher = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, self.session == current, self.isRecording else { return }
                let hasText = !self.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                switch VoicePause.decide(now: Date(), started: self.startedAt, lastChange: self.lastChange,
                                         lastLoud: self.lastLoud, hasText: hasText) {
                case .listen:
                    continue
                case .send:
                    self.stop(send: true)
                    return
                case .giveUp:
                    self.cancel()
                    return
                }
            }
        }
    }

    private func heard(_ value: Float) {
        guard isRecording else { return }
        level = value
        if value >= VoicePause.loudLevel {
            lastLoud = Date()
        }
    }

    private func stopEngine() {
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
    }

    private static func requestAccess() async -> Bool {
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}

/// Громкость в потоке звука с микрофона. Работает в звуковом потоке, отдаёт значение ~15 раз в секунду.
final class LevelMeter: @unchecked Sendable {
    private var count = 0

    func feed(_ buffer: AVAudioPCMBuffer) -> Float? {
        count += 1
        guard count % 3 == 0, let samples = buffer.floatChannelData?[0] else { return nil }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return nil }
        var sum: Float = 0
        for index in 0..<frames {
            sum += samples[index] * samples[index]
        }
        return VoicePause.level(rms: (sum / Float(frames)).squareRoot())
    }
}
