import AVFoundation

/// Summary of the last microphone session, written to
/// ~/Library/Application Support/NotchPrompter/voice-diagnostics.txt when the mic stops.
/// Only level statistics, never audio, so voice-mode problems can be diagnosed afterwards.
struct VoiceDiagnostics {
    private static let fileName = "voice-diagnostics.txt"
    private static let maxSamples = 60 * 60 * 50  // ~1 hour of 1024-frame buffers

    private var started = Date()
    private var formatDescription = ""
    private var levels: [Double] = []
    private var speakingCount = 0
    private var transitions = 0
    private var wasSpeaking = false

    mutating func begin(format: AVAudioFormat) {
        self = VoiceDiagnostics()
        formatDescription = "\(format.channelCount) ch, \(Int(format.sampleRate)) Hz"
        levels.reserveCapacity(4096)
    }

    mutating func record(_ db: Double, speaking: Bool) {
        guard levels.count < Self.maxSamples else { return }
        levels.append(db)
        if speaking { speakingCount += 1 }
        if speaking != wasSpeaking { transitions += 1; wasSpeaking = speaking }
    }

    func end(gate: SpeechGate) {
        let sorted = levels.sorted()
        func pct(_ p: Double) -> String {
            guard !sorted.isEmpty else { return "–" }
            return String(format: "%.1f", sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))])
        }
        let device = AVCaptureDevice.default(for: .audio)?.localizedName ?? "unknown"
        let report = """
        NotchPrompter voice diagnostics
        session:        \(started.formatted()) – \(Date().formatted(date: .omitted, time: .standard))
        input device:   \(device) (\(formatDescription))
        buffers:        \(levels.count) (~\(levels.count / 47) s)
        level dBFS:     min \(pct(0)) · p10 \(pct(0.1)) · median \(pct(0.5)) · p90 \(pct(0.9)) · max \(pct(1))
        noise floor:    \(String(format: "%.1f", gate.noiseFloor)) dBFS at end
        threshold:      \(String(format: "%.1f", gate.threshold)) dBFS (floor + \(String(format: "%.0f", gate.margin)) dB)
        speaking:       \(levels.isEmpty ? 0 : speakingCount * 100 / levels.count)% of the time, \(transitions) on/off changes

        """
        Persistence.writeText(report, to: Self.fileName)
    }
}
