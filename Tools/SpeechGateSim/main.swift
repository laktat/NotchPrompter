// Offline check for SpeechGate: synthesized speech (macOS `say`, Czech + English) is scaled to
// different mic levels, mixed with background noise and fed through the gate in the same
// 1024-frame blocks the app uses. Run with `make voice-sim`.
import AVFoundation

let sampleRate = 48000.0
let block = 1024

func load(_ path: String) -> [Float] {
    let file = try! AVAudioFile(forReading: URL(fileURLWithPath: path))
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try! file.read(into: buffer)
    return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
}

func rmsDB(_ x: ArraySlice<Float>) -> Double {
    let power = x.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(x.count, 1))
    return power > 0 ? max(-80, Double(10 * log10(power))) : -80
}

/// Scales the clip so its voiced blocks average `targetDB`.
func scaled(_ x: [Float], to targetDB: Double) -> [Float] {
    let blocks = stride(from: 0, to: x.count - block, by: block).map { rmsDB(x[$0..<$0 + block]) }
    let peak = blocks.max()!
    let voiced = blocks.filter { $0 > peak - 25 }
    let gain = Float(pow(10, (targetDB - voiced.reduce(0, +) / Double(voiced.count)) / 20))
    return x.map { $0 * gain }
}

func addNoise(_ x: inout [Float], db: Double) {
    let amp = Float(pow(10, db / 20))
    for i in x.indices {
        let u1 = Float.random(in: 1e-7..<1), u2 = Float.random(in: 0..<1)
        x[i] += amp * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

struct Result {
    var speechBlocks = 0, speechOn = 0, silenceBlocks = 0, silenceOn = 0, firstOn: Double?
}

/// `segments`: (seconds of silence or nil, clip or nil). Speech regions are the clips.
func simulate(_ segments: [[Float]?], silence: Double, speechDB: Double, noiseDB: Double) -> Result {
    var signal: [Float] = []
    var speech: [Range<Int>] = []
    for clip in segments {
        if let clip {
            let x = scaled(clip, to: speechDB)
            speech.append(signal.count..<signal.count + x.count)
            signal += x
        } else {
            signal += [Float](repeating: 0, count: Int(silence * sampleRate))
        }
    }
    addNoise(&signal, db: noiseDB)

    var gate = SpeechGate(margin: SpeechGate.margin(forSensitivity: 0.5))
    var r = Result()
    for (k, i) in stride(from: 0, to: signal.count - block, by: block).enumerated() {
        let t = Double(k * block) / sampleRate
        let on = gate.update(level: rmsDB(signal[i..<i + block]), at: t)
        if speech.contains(where: { $0.contains(i) }) {
            r.speechBlocks += 1
            if on { r.speechOn += 1; if r.firstOn == nil { r.firstOn = t } }
        } else if !speech.contains(where: { (i - $0.upperBound) < Int(0.6 * sampleRate) && i >= $0.upperBound }) {
            // Real silence, excluding the intended release tail after speech.
            r.silenceBlocks += 1
            if on { r.silenceOn += 1 }
        }
    }
    return r
}

let dir = CommandLine.arguments[1]
let cs = load("\(dir)/cs.wav"), en = load("\(dir)/en.wav")
var failed = false

func check(_ name: String, speechDB: Double, noiseDB: Double, leadIn: Bool = true,
           minSpeech: Double = 90, maxSilence: Double = 2) {
    let segments: [[Float]?] = leadIn ? [nil, cs, nil, en, nil] : [cs, nil]
    let r = simulate(segments, silence: leadIn ? 2.5 : 2, speechDB: speechDB, noiseDB: noiseDB)
    let speechPct = 100 * Double(r.speechOn) / Double(max(r.speechBlocks, 1))
    let silencePct = 100 * Double(r.silenceOn) / Double(max(r.silenceBlocks, 1))
    let ok = speechPct >= minSpeech && silencePct <= maxSilence
    failed = failed || !ok
    print(String(format: "%@ %-30@ speech %3.0f dB, noise %3.0f dB → moving %3.0f%% of speech, %3.0f%% of silence, starts after %.2fs",
                 ok ? "PASS" : "FAIL", name as NSString, speechDB, noiseDB, speechPct, silencePct, r.firstOn ?? -1))
}

check("quiet built-in mic", speechDB: -50, noiseDB: -64)
check("very quiet mic", speechDB: -56, noiseDB: -68)
check("normal mic", speechDB: -35, noiseDB: -60)
check("noisy room", speechDB: -35, noiseDB: -48)
check("loud headset mic", speechDB: -22, noiseDB: -55)
check("talking right away (no countdown)", speechDB: -50, noiseDB: -64, leadIn: false)
exit(failed ? 1 : 0)
