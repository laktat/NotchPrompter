import SwiftUI

/// Where each rendered line of the script starts, read from SwiftUI's own text layout
/// (`Text.LayoutKey`), so word positions match what's on screen exactly.
struct TextLineMap: Equatable {
    struct Line: Equatable {
        /// UTF-16 offset of the first character on the line.
        let start: Int
        /// Top of the line in the text's coordinate space.
        let top: CGFloat
    }

    private(set) var lines: [Line] = []

    static let empty = TextLineMap()

    private init() {}

    init(_ layouts: [Text.LayoutKey.AnchoredLayout]) {
        // The script is a single Text; its character indices are UTF-16 offsets.
        guard let layout = layouts.first?.layout,
              let zero = layout.first?.first?.characterIndices.first else { return }
        lines = layout.compactMap { line in
            guard let first = line.lazy.flatMap(\.characterIndices).min() else { return nil }
            return Line(start: zero.distance(to: first), top: line.typographicBounds.rect.minY)
        }
    }

    var isEmpty: Bool { lines.isEmpty }

    /// Top of the line containing the character at `utf16Offset`.
    func top(ofCharacterAt utf16Offset: Int) -> CGFloat {
        let index = lines.lastIndex { $0.start <= utf16Offset } ?? 0
        return lines.isEmpty ? 0 : lines[index].top
    }

    /// UTF-16 offset where the line at (or just below) `y` starts.
    func lineStart(atOrBelow y: CGFloat) -> Int {
        (lines.first { $0.top >= y - 1 } ?? lines.last)?.start ?? 0
    }
}
