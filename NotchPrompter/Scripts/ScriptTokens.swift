import Foundation

/// A word of the script: where it is in the text and how it compares to recognized speech.
struct ScriptToken: Equatable {
    let range: Range<String.Index>
    /// Same range as UTF-16 offsets: safe to bounds-check against a newer version of the text.
    let utf16Range: NSRange
    /// Lowercased, without diacritics and punctuation ("Dobrý," → "dobry").
    let normalized: String
}

enum ScriptTokenizer {
    /// Whitespace-separated words that contain at least one letter or digit.
    static func tokens(in text: String) -> [ScriptToken] {
        var tokens: [ScriptToken] = []
        var start: String.Index?
        for index in text.indices {
            if text[index].isWhitespace {
                if let s = start { append(s..<index) }
                start = nil
            } else if start == nil {
                start = index
            }
        }
        if let s = start { append(s..<text.endIndex) }
        return tokens

        func append(_ range: Range<String.Index>) {
            let normalized = normalize(text[range])
            if !normalized.isEmpty {
                tokens.append(ScriptToken(range: range, utf16Range: NSRange(range, in: text), normalized: normalized))
            }
        }
    }

    /// Same normalization for script and recognizer output, so "Dobrý," matches "dobry".
    static func normalize(_ word: some StringProtocol) -> String {
        let folded = String(word).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                          locale: nil)
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// Recognizer text → normalized words.
    static func words(in recognized: String) -> [String] {
        recognized.split(whereSeparator: \.isWhitespace).map(normalize).filter { !$0.isEmpty }
    }
}
