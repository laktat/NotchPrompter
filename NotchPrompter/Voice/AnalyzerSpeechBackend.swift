import AVFoundation
import Speech

/// macOS 26+: SpeechAnalyzer with DictationTranscriber. Runs fully on-device and, unlike
/// SFSpeechRecognizer on this generation of macOS, has an on-device Czech model.
@available(macOS 26, *)
final class AnalyzerSpeechBackend: SpeechBackend, @unchecked Sendable {
    enum ModelStatus: Equatable {
        case installed
        case notInstalled
        case unsupported
    }

    private let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let converter: AVAudioConverter?
    private let analyzerFormat: AVAudioFormat
    private var results: Task<Void, Never>?

    private init(analyzer: SpeechAnalyzer, input: AsyncStream<AnalyzerInput>.Continuation,
                 converter: AVAudioConverter?, analyzerFormat: AVAudioFormat) {
        self.analyzer = analyzer
        self.input = input
        self.converter = converter
        self.analyzerFormat = analyzerFormat
    }

    // MARK: Model

    static func transcriber(for locale: Locale) async -> DictationTranscriber? {
        guard let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) else { return nil }
        return DictationTranscriber(locale: supported, contentHints: [], transcriptionOptions: [],
                                    reportingOptions: [.volatileResults, .frequentFinalization],
                                    attributeOptions: [])
    }

    static func modelStatus(for locale: Locale) async -> ModelStatus {
        guard let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) else { return .unsupported }
        let installed = await DictationTranscriber.installedLocales
        return installed.contains { $0.identifier(.bcp47) == supported.identifier(.bcp47) } ? .installed : .notInstalled
    }

    /// Asks macOS to download the on-device model (a one-time system download, like adding a
    /// dictation language). `progress` is called on the main actor with 0…1.
    static func downloadModel(for locale: Locale, progress: @escaping @MainActor (Double) -> Void) async throws {
        guard let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale),
              let transcriber = await transcriber(for: supported) else { return }
        _ = try? await AssetInventory.reserve(locale: supported)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else { return }
        let reporter = Task { @MainActor in
            while !Task.isCancelled {
                progress(request.progress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { reporter.cancel() }
        try await request.downloadAndInstall()
        await MainActor.run { progress(1) }
    }

    // MARK: Running

    static func start(locale: Locale, name: String, inputFormat: AVAudioFormat,
                      onEvent: @escaping SpeechEventHandler) async throws -> AnalyzerSpeechBackend {
        guard let transcriber = await transcriber(for: locale) else {
            throw SpeechTrackerError.unsupportedLanguage(name)
        }
        guard await modelStatus(for: locale) == .installed else {
            throw SpeechTrackerError.modelNotInstalled(name)
        }
        // Keep the model reserved for this app so macOS doesn't reclaim it.
        if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            _ = try? await AssetInventory.reserve(locale: supported)
        }

        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber],
                                                                   considering: inputFormat) ?? inputFormat
        let converter = format == inputFormat ? nil : AVAudioConverter(from: inputFormat, to: format)
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.start(inputSequence: stream)

        let backend = AnalyzerSpeechBackend(analyzer: analyzer, input: continuation,
                                            converter: converter, analyzerFormat: format)
        backend.results = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    deliver(result.isFinal ? .final(text) : .partial(text), to: onEvent)
                }
            } catch {
                NSLog("NotchPrompter: transcription ended: \(error)")
            }
        }
        return backend
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else {
            input.yield(AnalyzerInput(buffer: buffer))
            return
        }
        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status != .error, output.frameLength > 0 {
            input.yield(AnalyzerInput(buffer: output))
        }
    }

    func stop() async {
        input.finish()
        await analyzer.cancelAndFinishNow()
        results?.cancel()
    }
}
