// Offline check for WordMatcher: a simulated speaker reads the script through a simulated
// recognizer that makes realistic mistakes. Run with `make tracker-sim`.
import Foundation

let script = """
Dobrý den, vítejte u dnešního videa. Dnes si ukážeme, jak funguje čtecí zařízení přímo pod kamerou. \
Text se posouvá podle toho, co právě říkáte, takže se nemusíte starat o rychlost. Když se odmlčíte, \
text počká. Když přeskočíte větu, aplikace vás najde o kousek dál. A teď přejdeme k angličtině.

Hello and welcome back. Today I want to show you how this teleprompter works, right under the camera. \
The text follows what you are saying, so you never have to think about the speed. If you pause, the \
text waits for you. If you skip a sentence, the app finds you a little further ahead. Thanks for \
watching, and see you in the next video. The text follows what you are saying, again, as a repeated phrase.
"""

let tokens = ScriptTokenizer.tokens(in: script)
let words = tokens.map(\.normalized)
let spoken = tokens.map { String(script[$0.range]) }

struct Rng { var s: UInt64; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) } }

/// Recognizer error model applied to one spoken word.
func recognize(_ word: String, rng: inout Rng, errorRate: Double) -> [String] {
    let r = rng.next()
    if r < errorRate * 0.4 { return ["xyzzy\(Int(rng.next() * 100))"] }              // wrong word
    if r < errorRate * 0.6 { return [] }                                              // dropped
    if r < errorRate * 0.8 { return [word, ["ehm", "the", "a", "no"][Int(rng.next() * 4)]] } // filler inserted
    if r < errorRate { return [String(word.dropLast(min(2, max(0, word.count - 4))))] }  // truncated
    // Recognizers often drop diacritics or change case; normalization must cope.
    return [rng.next() < 0.3 ? word.folding(options: .diacriticInsensitive, locale: nil).lowercased() : word]
}

struct Outcome { var within1 = 0, total = 0, maxLag = 0, backJumps = 0, final = -1, falseJumps = 0 }

/// `plan`: sequence of script indices the speaker says (or -1 for an off-script word).
func run(_ name: String, plan: [Int], errorRate: Double, seed: UInt64, offScript: [String] = [],
         expectFinal: Int, check: (Int, Int) -> Bool = { _, _ in true }) -> Bool {
    var rng = Rng(s: seed)
    var matcher = WordMatcher(script: words)
    var transcript: [String] = []
    var o = Outcome()
    var lastPos = -1
    var off = offScript.makeIterator()
    var truth = -1
    for step in plan {
        let raw = step >= 0 ? recognize(spoken[step], rng: &rng, errorRate: errorRate) : [off.next() ?? "hmm"]
        if step >= 0 { truth = step }
        // Partial results arrive word by word; sometimes the last word is first heard wrong, then revised.
        for word in raw {
            if rng.next() < 0.15 {
                transcript.append("blah")
                matcher.update(recognized: ScriptTokenizer.words(in: transcript.joined(separator: " ")))
                transcript.removeLast()
            }
            transcript.append(word)
            matcher.update(recognized: ScriptTokenizer.words(in: transcript.suffix(40).joined(separator: " ")))
        }
        let pos = matcher.position
        if pos < lastPos { o.backJumps += 1 }
        if pos > truth + 2 { o.falseJumps += 1 }
        lastPos = pos
        if step >= 0 {
            o.total += 1
            if abs(pos - truth) <= 1 { o.within1 += 1 }
            o.maxLag = max(o.maxLag, truth - pos)
        }
    }
    o.final = matcher.position
    let pct = 100 * Double(o.within1) / Double(max(o.total, 1))
    let ok = pct >= 85 && o.falseJumps == 0 && abs(o.final - expectFinal) <= 1 && check(o.maxLag, o.backJumps)
    print(String(format: "%@ %@: within ±1 word %3.0f%%, max lag %d, back jumps %d, false jumps %d, final %d/%d",
                 ok ? "PASS" : "FAIL", name, pct, o.maxLag, o.backJumps, o.falseJumps, o.final, expectFinal))
    return ok
}

let all = Array(words.indices)
let last = words.count - 1
var ok = true
print("script: \(words.count) words")
ok = run("clean reading", plan: all, errorRate: 0.0, seed: 1, expectFinal: last) && ok
ok = run("10% recognition errors", plan: all, errorRate: 0.10, seed: 2, expectFinal: last) && ok
ok = run("20% recognition errors", plan: all, errorRate: 0.20, seed: 3, expectFinal: last) && ok
// Skip one sentence (indices 22..<36 not read).
let skip = all.filter { !(22..<36).contains($0) }
ok = run("skips a sentence", plan: skip, errorRate: 0.1, seed: 4, expectFinal: last) && ok
// Ad-libs 8 off-script words in the middle.
let adlib = Array(all[0..<30]) + [Int](repeating: -1, count: 8) + Array(all[30...])
ok = run("ad-libs off script", plan: adlib, errorRate: 0.1, seed: 5,
         offScript: ["tak", "jo", "to", "je", "vlastně", "docela", "fajn", "no"], expectFinal: last) && ok
// Skips a whole paragraph (jumps from Czech straight to "Today I want…").
let englishStart = words.firstIndex(of: "today")!
let jump = Array(all[0..<10]) + Array(all[englishStart...])
ok = run("skips a paragraph", plan: jump, errorRate: 0.05, seed: 6, expectFinal: last) && ok
exit(ok ? 0 : 1)
