import AVFoundation
import Observation
import Speech

/// Word tracking: recognizes speech on-device and follows it through the script.
/// macOS 26+ uses SpeechAnalyzer (Czech + English); older systems use SFSpeechRecognizer
/// with on-device recognition required (English only). Audio never leaves the Mac.
@MainActor
@Observable
final class SpeechTracker {
    enum Status: Equatable {
        case idle
        case preparing
        case listening
        /// The language's on-device model isn't installed yet (macOS 26+: one-time download).
        case needsModel
        case unavailable(String)
    }

    enum ModelStatus: Equatable {
        case unknown
        case installed
        case notInstalled
        case downloading(Double)
        case unsupported(String)
    }

    static let languages: [(id: String, name: String)] = [
        ("cs-CZ", "Čeština"),
        ("en-US", "English (US)"),
        ("en-GB", "English (UK)"),
    ]

    static func languageName(_ id: String) -> String {
        languages.first { $0.id == id }?.name ?? id
    }

    private(set) var status: Status = .idle
    private(set) var modelStatus: ModelStatus = .unknown
    /// Index into `tokens` of the last word you said; -1 before the first.
    private(set) var currentWord = -1
    private(set) var tokens: [ScriptToken] = []
    /// The last few recognized words, shown in Settings while testing.
    private(set) var heard = ""

    /// False when tracking can't work; callers fall back to fixed-speed scrolling.
    var isUsable: Bool {
        switch status {
        case .needsModel, .unavailable: false
        default: true
        }
    }

    /// Why tracking isn't running (or what it's waiting for), for the overlay and the menu.
    var problem: String? {
        if case .downloading(let fraction) = modelStatus {
            return "Downloading the \(languageName) speech model… \(Int(fraction * 100))%"
        }
        switch status {
        case .needsModel: return "The \(languageName) speech model isn't installed."
        case .unavailable(let message): return message
        default: return nil
        }
    }

    var languageName: String { Self.languageName(languageID) }

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var matcher = WordMatcher(script: [])
    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var backend: SpeechBackend?
    @ObservationIgnored private var wantsRunning = false
    @ObservationIgnored private var isStarting = false
    /// Set when starting failed; no retries until the next play (avoids a retry every countdown tick).
    @ObservationIgnored private var hasFailed = false
    @ObservationIgnored private var committed: [String] = []
    @ObservationIgnored private var pending: [String] = []
    @ObservationIgnored private var text: String?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    private var languageID: String { settings.settings.speechLocale }

    // MARK: Script

    func load(text: String) {
        self.text = text
        tokens = ScriptTokenizer.tokens(in: text)
        matcher = WordMatcher(script: tokens.map(\.normalized), position: matcher.position)
        currentWord = matcher.position
    }

    /// Continue tracking from just before `word` (after a rewind, script change or manual scroll).
    func reset(toWord word: Int) {
        matcher.reset(to: word - 1)
        currentWord = matcher.position
        committed = []
        pending = []
    }

    // MARK: Permissions & model

    func requestPermissions() async {
        guard await SpeechPermissions.request() else {
            status = .unavailable("Microphone or speech recognition access is off. Turn it on in System Settings → Privacy & Security.")
            return
        }
        if case .unavailable = status { status = .idle }
    }

    func refreshModelStatus() async {
        let locale = Locale(identifier: languageID)
        if #available(macOS 26, *) {
            switch await AnalyzerSpeechBackend.modelStatus(for: locale) {
            case .installed: modelStatus = .installed
            case .notInstalled: modelStatus = .notInstalled
            case .unsupported: modelStatus = .unsupported(SpeechTrackerError.unsupportedLanguage(languageName).localizedDescription)
            }
        } else {
            let onDevice = SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition ?? false
            modelStatus = onDevice ? .installed : .unsupported(SpeechTrackerError.needsNewerMacOS(languageName).localizedDescription)
        }
        // A model that just became available clears an earlier "not installed" state.
        if modelStatus == .installed, status == .needsModel { status = .idle }
    }

    func downloadModel() async {
        guard #available(macOS 26, *) else { return }
        modelStatus = .downloading(0)
        do {
            try await AnalyzerSpeechBackend.downloadModel(for: Locale(identifier: languageID)) { [weak self] fraction in
                self?.modelStatus = .downloading(fraction)
            }
        } catch {
            modelStatus = .unsupported("Download failed: \(error.localizedDescription)")
            return
        }
        await refreshModelStatus()
        // Already playing? Start tracking right away.
        if modelStatus == .installed, wantsRunning, audioEngine == nil {
            hasFailed = false
            start()
        }
    }

    // MARK: Start / stop

    func start() {
        wantsRunning = true
        guard audioEngine == nil, !isStarting, !hasFailed else { return }
        isStarting = true
        status = .preparing
        Task {
            await begin()
            isStarting = false
        }
    }

    func stop() {
        wantsRunning = false
        hasFailed = false
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        if let backend { Task { await backend.stop() } }
        backend = nil
        committed = []
        pending = []
        if status == .listening || status == .preparing { status = .idle }
    }

    private func begin() async {
        guard await SpeechPermissions.request() else {
            fail(.unavailable("Microphone or speech recognition access is off. Turn it on in System Settings → Privacy & Security."))
            return
        }
        guard wantsRunning else { return }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail(.unavailable(SpeechTrackerError.noMicrophone.localizedDescription))
            return
        }

        let backend: SpeechBackend
        do {
            backend = try await makeBackend(inputFormat: format)
        } catch SpeechTrackerError.modelNotInstalled {
            fail(.needsModel)
            return
        } catch {
            fail(.unavailable(error.localizedDescription))
            return
        }
        guard wantsRunning else {
            await backend.stop()
            return
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            backend.append(buffer)
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            await backend.stop()
            fail(.unavailable("Couldn't start the microphone: \(error.localizedDescription)"))
            return
        }
        self.backend = backend
        audioEngine = engine
        status = .listening
    }

    private func fail(_ status: Status) {
        self.status = status
        hasFailed = true
    }

    private func makeBackend(inputFormat: AVAudioFormat) async throws -> SpeechBackend {
        let locale = Locale(identifier: languageID)
        let handler: SpeechEventHandler = { [weak self] event in self?.handle(event) }
        if #available(macOS 26, *) {
            return try await AnalyzerSpeechBackend.start(locale: locale, name: languageName,
                                                         inputFormat: inputFormat, onEvent: handler)
        }
        return try LegacySpeechBackend(locale: locale, name: languageName,
                                       contextualStrings: distinctiveWords(), onEvent: handler)
    }

    /// Names and long words from the script help the recognizer spell them like the script does.
    private func distinctiveWords() -> [String] {
        guard let text = text else { return [] }
        var seen = Set<String>()
        return tokens.compactMap { token -> String? in
            let word = String(text[token.range]).trimmingCharacters(in: .punctuationCharacters)
            guard word.count >= 6 || word.first?.isUppercase == true, seen.insert(word.lowercased()).inserted else { return nil }
            return word
        }
        .prefix(100)
        .map { $0 }
    }

    // MARK: Recognition → position

    private func handle(_ event: SpeechEvent) {
        // Ignore late events from a recognizer that was just stopped.
        guard backend != nil else { return }
        switch event {
        case .partial(let text):
            pending = ScriptTokenizer.words(in: text)
            heard = String(text.suffix(60))
        case .final(let text):
            committed = Array((committed + ScriptTokenizer.words(in: text)).suffix(40))
            pending = []
            heard = String(text.suffix(60))
        }
        let recent = committed + pending
        if matcher.update(recognized: recent) {
            currentWord = matcher.position
        }
    }

    // MARK: Debug

    /// Development aid (see DebugSnapshot): streams an audio file through the real recognition
    /// path in real time, instead of the microphone. Returns the word index after each event.
    func debugRun(file url: URL, languageID: String) async -> [String] {
        var log: [String] = []
        guard let file = try? AVAudioFile(forReading: url) else { return ["cannot open \(url.path)"] }
        let format = file.processingFormat
        let handler: SpeechEventHandler = { [weak self] event in
            guard let self else { return }
            self.handle(event)
            log.append("\(self.currentWord)")
        }
        do {
            let locale = Locale(identifier: languageID)
            let name = Self.languageName(languageID)
            let backend: SpeechBackend
            if #available(macOS 26, *) {
                backend = try await AnalyzerSpeechBackend.start(locale: locale, name: name, inputFormat: format, onEvent: handler)
            } else {
                backend = try LegacySpeechBackend(locale: locale, name: name, contextualStrings: [], onEvent: handler)
            }
            self.backend = backend
            let chunk: AVAudioFrameCount = 2048
            while file.framePosition < file.length {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk),
                      (try? file.read(into: buffer, frameCount: chunk)) != nil else { break }
                backend.append(buffer)
                try? await Task.sleep(for: .seconds(Double(buffer.frameLength) / format.sampleRate))
            }
            // Two seconds of silence after the recording, as when a speaker stops talking.
            for _ in 0..<Int(2 * format.sampleRate / Double(chunk)) {
                guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { break }
                silence.frameLength = chunk  // zero-filled
                backend.append(silence)
                try? await Task.sleep(for: .seconds(Double(chunk) / format.sampleRate))
            }
            self.backend = nil
            await backend.stop()
        } catch {
            log.append("error: \(error.localizedDescription)")
        }
        return log
    }
}
