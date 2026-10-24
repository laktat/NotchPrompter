import Foundation

/// Follows a speaker through the script by aligning the most recent recognized words with the
/// script around the current position. Pure logic, no speech APIs, so it can be tested offline
/// (`make tracker-sim`).
struct WordMatcher {
    /// How many recent recognized words are aligned.
    static let tailLength = 6
    /// How far ahead of the current position a match may land (≈ 10–15 s of speech).
    static let lookahead = 30
    /// Small corrections backwards (recognizer revising a partial result) are allowed.
    static let lookbehind = 3
    /// Two well-matched words (or one long one right ahead) are needed to move.
    static let minScore = 1.55
    /// Outside the local window only a long run of matching words counts (skipped a paragraph).
    static let globalMinScore = 4.2

    let script: [String]
    /// Index of the last spoken script word; -1 before the first word.
    private(set) var position: Int

    init(script: [String], position: Int = -1) {
        self.script = script
        self.position = min(max(position, -1), script.count - 1)
    }

    mutating func reset(to position: Int) {
        self.position = min(max(position, -1), script.count - 1)
    }

    /// `recognized`: recent normalized recognizer words, oldest first. Returns true if the position moved.
    @discardableResult
    mutating func update(recognized: [String]) -> Bool {
        let tail = Array(recognized.suffix(Self.tailLength))
        guard !tail.isEmpty, !script.isEmpty else { return false }

        let lower = max(0, position - Self.lookbehind)
        let upper = min(script.count - 1, position + Self.lookahead)
        var best: (index: Int, value: Double)?

        if lower <= upper {
            for end in lower...upper {
                guard let score = score(tail: tail, end: end) else { continue }
                let distance = end - (position + 1)
                let required = end <= position ? 2.5  // moving back needs strong evidence
                    : (distance <= 3 && script[end].count >= 6 ? 0.85 : Self.minScore)
                guard score >= required else { continue }
                let value = score - 0.03 * Double(abs(distance))
                if best == nil || value > best!.value { best = (end, value) }
            }
        }

        if best == nil, tail.count >= 5 {
            for end in script.indices where end < lower || end > upper {
                guard let score = score(tail: tail, end: end), score >= Self.globalMinScore else { continue }
                if best == nil || score > best!.value { best = (end, score) }
            }
        }

        guard let best, best.index != position else { return false }
        position = best.index
        return true
    }

    // MARK: Scoring

    /// Alignment score of `tail` ending at script word `end`, or nil if the newest word doesn't
    /// match there. Recognized and script words may each be skipped (recognizer drops or merges words).
    private func score(tail: [String], end: Int) -> Double? {
        let anchor = Self.similarity(tail[tail.count - 1], script[end])
        guard anchor >= 0.7 else { return nil }

        // Align the rest backwards: rows = recognized words, columns = script words before `end`.
        let rest = tail.dropLast().reversed().map { $0 }
        let window = min(end, rest.count + 2)
        guard !rest.isEmpty, window > 0 else { return anchor }

        let gap = 0.45
        var previous = [Double](repeating: 0, count: window + 1)
        for k in 1...window { previous[k] = -gap * Double(k) }
        var bestRow = 0.0
        for (i, word) in rest.enumerated() {
            var row = [Double](repeating: 0, count: window + 1)
            row[0] = -gap * Double(i + 1)
            for k in 1...window {
                let sim = Self.similarity(word, script[end - k])
                let match = previous[k - 1] + (sim >= 0.7 ? sim : -0.6)
                row[k] = max(match, previous[k] - gap, row[k - 1] - gap)
            }
            previous = row
            // Older words that don't match shouldn't cancel out a good recent match.
            bestRow = max(bestRow, row.max() ?? 0)
        }
        return anchor + bestRow
    }

    /// 1 for equal words, less for near misses (recognizer spelling, case endings), 0 for different words.
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let shorter = min(a.count, b.count), longer = max(a.count, b.count)
        guard shorter >= 3 else { return 0 }
        // Czech case endings: "kamerou" vs "kamera" share a long prefix.
        let prefix = zip(a, b).prefix { $0 == $1 }.count
        if prefix >= 4, Double(prefix) / Double(longer) >= 0.6 { return 0.8 }
        let distance = levenshtein(Array(a), Array(b))
        let ratio = 1 - Double(distance) / Double(longer)
        return ratio >= 0.7 ? ratio : 0
    }

    /// Edit distance; callers guarantee both words are non-empty.
    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]
            row[0] = i
            for j in 1...b.count {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return row[b.count]
    }
}
