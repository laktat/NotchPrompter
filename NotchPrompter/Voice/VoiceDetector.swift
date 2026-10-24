import AVFoundation
import QuartzCore
import Observation

/// Listens to the microphone level and reports whether you're speaking.
/// Only the level is computed; no audio is stored or sent anywhere.
@MainActor
@Observable
final class VoiceDetector {
    enum Permission {
        case unknown
        case granted
        case denied
    }

    nonisolated static let floorDB = -80.0

    private(set) var permission: Permission
    private(set) var isRunning = false
    private(set) var isSpeaking = false
    /// Latest input level in dBFS, `floorDB`…0.
    private(set) var level = VoiceDetector.floorDB
    /// Current speaking threshold: the tracked background level plus the sensitivity margin.
    private(set) var thresholdDB = VoiceDetector.floorDB
    private(set) var errorMessage: String?

    /// False when voice mode can't work (no permission, no mic); callers fall back to fixed speed.
    var isUsable: Bool { permission != .denied && errorMessage == nil }

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var configObserver: NSObjectProtocol?
    @ObservationIgnored private var wantsRunning = false
    @ObservationIgnored private var pendingRequest: Task<Bool, Never>?
    @ObservationIgnored private var gate = SpeechGate(margin: 12)
    @ObservationIgnored private var diagnostics = VoiceDiagnostics()

    init(settings: SettingsStore) {
        self.settings = settings
        permission = Self.systemPermission()
    }

    // MARK: Permission

    /// Shows the system prompt the first time; afterwards just reports the stored answer.
    /// Concurrent callers share one prompt and all get its answer.
    @discardableResult
    func requestPermission() async -> Bool {
        permission = Self.systemPermission()
        guard permission == .unknown else { return permission == .granted }

        let request = pendingRequest ?? Task { await AVCaptureDevice.requestAccess(for: .audio) }
        pendingRequest = request
        let granted = await request.value
        pendingRequest = nil
        permission = granted ? .granted : .denied
        return granted
    }

    private static func systemPermission() -> Permission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .denied, .restricted: .denied
        default: .unknown
        }
    }

    // MARK: Start / stop

    func start() {
        wantsRunning = true
        guard !isRunning else { return }
        Task {
            guard await requestPermission(), wantsRunning, !isRunning else { return }
            startEngine()
        }
    }

    func stop() {
        wantsRunning = false
        stopEngine()
    }

    private func startEngine() {
        // Touch inputNode only after permission is granted: accessing it can trigger the prompt.
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorMessage = "No microphone found."
            return
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let db = VoiceDetector.decibels(of: buffer)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.process(db) }
            }
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            errorMessage = "Couldn't start the microphone: \(error.localizedDescription)"
            return
        }

        audioEngine = engine
        isRunning = true
        errorMessage = nil
        gate = SpeechGate(margin: margin)
        diagnostics.begin(format: format)
        // Input device changed (headset plugged in, AirPods connected): rebuild on the new device.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.wantsRunning else { return }
                self.stopEngine()
                self.startEngine()
            }
        }
    }

    private func stopEngine() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            diagnostics.end(gate: gate)
        }
        audioEngine = nil
        if isRunning { isRunning = false }
        if isSpeaking { isSpeaking = false }
        level = Self.floorDB
    }

    // MARK: Level → speaking

    private var margin: Double { SpeechGate.margin(forSensitivity: settings.settings.voiceSensitivity) }

    private func process(_ db: Double) {
        guard isRunning else { return }
        gate.margin = margin
        let speaking = gate.update(level: db, at: CACurrentMediaTime())
        diagnostics.record(db, speaking: speaking)
        level = db
        thresholdDB = gate.threshold
        if isSpeaking != speaking { isSpeaking = speaking }
    }

    /// RMS of the first channel in dBFS. Runs on the audio thread.
    nonisolated static func decibels(of buffer: AVAudioPCMBuffer) -> Double {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return floorDB }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += samples[i] * samples[i] }
        let rms = (sum / Float(count)).squareRoot()
        guard rms > 0 else { return floorDB }
        return max(floorDB, Double(20 * log10(rms)))
    }
}
