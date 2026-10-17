import Foundation
import AVFoundation
import Speech

/// Своя кнопка микрофона: русская речь → текст в поле ввода.
@MainActor
final class Dictation: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    @Published var error: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() async {
        guard !isRecording else { return }
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

            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()

            transcript = ""
            isRecording = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                let text = result?.bestTranscription.formattedString
                let ended = (result?.isFinal ?? false) || failure != nil
                Task { @MainActor in
                    guard let self else { return }
                    if let text { self.transcript = text }
                    if ended { self.finish() }
                }
            }
        } catch {
            self.error = "Не удалось включить микрофон"
            finish()
        }
    }

    /// «Стоп»: дослушиваем последние слова, через полторы секунды закрываем всё сами.
    func stop() {
        guard isRecording else { return }
        request?.endAudio()
        stopEngine()
        isRecording = false
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.finish()
        }
    }

    private func finish() {
        stopEngine()
        request?.endAudio()
        request = nil
        task?.finish()
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
