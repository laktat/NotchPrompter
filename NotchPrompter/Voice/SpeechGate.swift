import Foundation

/// Decides "speaking or not" from a stream of input levels (dBFS).
///
/// The threshold is relative to a tracked background-noise floor rather than a fixed level,
/// so it works with a quiet built-in mic at low input volume as well as in a noisy room.
struct SpeechGate {
    /// Level must stay above the threshold this long to count as speech (ignores clicks).
    static let attack: Double = 0.04
    /// Keep "speaking" this long after the level drops, so pauses between words don't stop the text.
    static let release: Double = 0.45
    /// The floor follows quieter input quickly…
    static let floorFallTime: Double = 0.3
    /// …but rises slowly, so speech doesn't drag it up. Gaps between words pull it back down.
    /// In a loud room it takes ~1–2 s to climb to the noise level; the mic starts during the
    /// countdown, so that happens before the text starts moving.
    static let floorRisePerSecond: Double = 3
    /// Never treat digital near-silence as speech.
    static let minimumThreshold: Double = -70

    /// How far above the noise floor speech has to be, in dB.
    var margin: Double

    private(set) var noiseFloor: Double = -60
    private(set) var isSpeaking = false
    private var lastTime: Double?
    private var aboveSince: Double?
    private var lastAbove: Double = 0

    init(margin: Double) {
        self.margin = margin
    }

    var threshold: Double { max(noiseFloor + margin, Self.minimumThreshold) }

    /// Sensitivity 0 needs speech 18 dB above the background, 1 only 6 dB.
    static func margin(forSensitivity sensitivity: Double) -> Double {
        18 - min(max(sensitivity, 0), 1) * 12
    }

    @discardableResult
    mutating func update(level db: Double, at time: Double) -> Bool {
        let dt = lastTime.map { min(max(time - $0, 0), 0.5) } ?? 0
        lastTime = time

        // Decide against the floor as it was before this sample.
        let above = db >= threshold
        if above {
            let since = aboveSince ?? time
            aboveSince = since
            lastAbove = time
            if !isSpeaking, time - since >= Self.attack { isSpeaking = true }
        } else {
            aboveSince = nil
            if isSpeaking, time - lastAbove > Self.release { isSpeaking = false }
        }

        trackFloor(db, dt: dt)
        return isSpeaking
    }

    private mutating func trackFloor(_ db: Double, dt: Double) {
        if db < noiseFloor {
            noiseFloor += (db - noiseFloor) * min(1, dt / Self.floorFallTime)
        } else {
            noiseFloor = min(db, noiseFloor + Self.floorRisePerSecond * dt)
        }
    }
}
