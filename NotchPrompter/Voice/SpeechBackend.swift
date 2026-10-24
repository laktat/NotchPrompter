import AVFoundation
import Speech

/// What a recognizer reports: `partial` replaces the text not yet final, `final` commits it.
enum SpeechEvent {
    case partial(String)
    case final(String)
}

enum SpeechTrackerError: LocalizedError {
    case unsupportedLanguage(String)
    case modelNotInstalled(String)
    case needsNewerMacOS(String)
    case noMicrophone

    var errorDescription: String? {
        switch self {
        case .unsupportedLanguage(let name):
            "On-device speech recognition for \(name) isn't available on this Mac."
        case .modelNotInstalled(let name):
            "The \(name) speech model isn't installed yet. Download it in Settings → Scrolling."
        case .needsNewerMacOS(let name):
            "On-device recognition for \(name) needs macOS 26 or later."
        case .noMicrophone:
            "No microphone found."
        }
    }
}

/// A running recognizer. `append` is called on the audio thread.
protocol SpeechBackend: AnyObject, Sendable {
    func append(_ buffer: AVAudioPCMBuffer)
    func stop() async
}

/// Delivers recognizer events on the main actor.
typealias SpeechEventHandler = @MainActor (SpeechEvent) -> Void

func deliver(_ event: SpeechEvent, to handler: @escaping SpeechEventHandler) {
    DispatchQueue.main.async {
        MainActor.assumeIsolated { handler(event) }
    }
}

/// SFSpeechRecognizer with on-device recognition required (used before macOS 26).
/// A recognition request ends after a final result or a long silence, so a new one is
/// started each time; the audio tap always feeds the current request.
final class LegacySpeechBackend: SpeechBackend, @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer
    private let contextualStrings: [String]
    private let onEvent: SpeechEventHandler
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var stopped = false

    init(locale: Locale, name: String, contextualStrings: [String], onEvent: @escaping SpeechEventHandler) throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw SpeechTrackerError.unsupportedLanguage(name)
        }
        // Never fall back to Apple's servers: the app works offline only.
        guard recognizer.supportsOnDeviceRecognition else {
            throw SpeechTrackerError.needsNewerMacOS(name)
        }
        self.recognizer = recognizer
        self.contextualStrings = contextualStrings
        self.onEvent = onEvent
        beginRequest()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = request
        lock.unlock()
        request?.append(buffer)
    }

    func stop() async {
        let (request, task) = lock.withLock {
            stopped = true
            defer { (self.request, self.task) = (nil, nil) }
            return (self.request, self.task)
        }
        request?.endAudio()
        task?.cancel()
    }

    private func beginRequest() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        request.contextualStrings = contextualStrings

        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self, weak request] result, error in
            guard let self, let request else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                deliver(result.isFinal ? .final(text) : .partial(text), to: self.onEvent)
            }
            if error != nil || result?.isFinal == true {
                // Errors are usually "no speech detected" after a silence: just listen again.
                self.restart(replacing: request, after: error == nil ? 0 : 0.3)
            }
        }
    }

    private func restart(replacing finished: SFSpeechAudioBufferRecognitionRequest, after delay: TimeInterval) {
        lock.lock()
        // A late callback from an older request must not start a second one.
        let isCurrent = request === finished
        if isCurrent { request = nil }
        let stopped = stopped
        lock.unlock()
        finished.endAudio()
        guard isCurrent, !stopped else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in self?.beginRequest() }
    }
}
