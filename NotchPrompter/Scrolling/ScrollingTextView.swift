import SwiftUI

/// Word tracking: the word you just said, as UTF-16 offsets into the script text.
struct WordHighlight: Equatable {
    let current: NSRange

    static let color = Color(red: 1, green: 0.82, blue: 0.25)
    static let readOpacity = 0.45
}

/// The script, offset by the engine, clipped to the text area and faded at both edges.
struct ScrollingTextView: View {
    let text: String
    let settings: PrompterSettings
    let engine: ScrollEngine
    var highlight: WordHighlight?

    var body: some View {
        GeometryReader { geo in
            let fade = fadeHeights(for: geo.size.height)
            ScriptText(text: text.isEmpty ? Self.placeholder : text,
                       fontSize: settings.fontSize,
                       lineSpacing: settings.lineSpacing,
                       color: settings.textColor.color,
                       highlight: text.isEmpty ? nil : highlight)
                .frame(width: geo.size.width)
                .background {
                    GeometryReader { textGeo in
                        Color.clear.preference(key: ContentHeightKey.self, value: textGeo.size.height)
                    }
                }
                // First line starts just below the top fade, then moves up.
                .offset(y: fade.top - engine.offset)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .clipped()
                .mask {
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: fade.top / geo.size.height),
                        .init(color: .black, location: 1 - fade.bottom / geo.size.height),
                        .init(color: .clear, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
        }
        .onPreferenceChange(ContentHeightKey.self) { height in
            engine.contentHeight = height
        }
        .onPreferenceChange(Text.LayoutKey.self) { layouts in
            let lines = text.isEmpty ? .empty : TextLineMap(layouts)
            if engine.textLines != lines { engine.textLines = lines }
        }
    }

    private static let placeholder = "No script selected — open the editor from the menu bar."

    private func fadeHeights(for height: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        guard height > 0 else { return (0, 0) }
        return (min(14, height * 0.12), min(40, height * 0.28))
    }
}

/// Kept separate (and Equatable) so a new offset every frame doesn't re-evaluate the text.
private struct ScriptText: View, Equatable {
    let text: String
    let fontSize: Double
    let lineSpacing: Double
    let color: Color
    let highlight: WordHighlight?

    var body: some View {
        Text(attributed)
            .font(.system(size: fontSize, weight: .semibold))
            .lineSpacing(lineSpacing)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Only colours change, never fonts, so highlighting never moves line breaks.
    private var attributed: AttributedString {
        let display = Self.singleParagraph(text)
        var result = AttributedString(display)
        guard let highlight,
              let word = Range(highlight.current, in: display),
              let wordRange = Range(word, in: result) else { return result }
        result[result.startIndex..<wordRange.lowerBound].foregroundColor = color.opacity(WordHighlight.readOpacity)
        result[wordRange].foregroundColor = WordHighlight.color
        return result
    }

    /// Paragraph breaks become U+2028 line separators: it looks the same, but SwiftUI then reports
    /// one paragraph whose character indices are UTF-16 offsets into the whole script (with real
    /// paragraphs they restart at 0 in each one). Each unit maps to one unit, so offsets stay valid.
    static func singleParagraph(_ text: String) -> String {
        let units = text.utf16.map { [0x0A, 0x0D, 0x85, 0x2029].contains($0) ? 0x2028 : $0 }
        return String(utf16CodeUnits: units, count: units.count)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
