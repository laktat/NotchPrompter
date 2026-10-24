import Foundation

struct Script: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var text: String
    var modified = Date()

    var wordCount: Int { Script.words(in: text).count }

    /// Words as the prompter sees them: whitespace-separated tokens.
    static func words(in text: String) -> [Substring] {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
    }

    /// Reading time at the given pace, e.g. "2:35".
    func duration(atWPM wpm: Double) -> String {
        let seconds = Int((Double(wordCount) / max(wpm, 1) * 60).rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static let welcome = Script(
        title: "Welcome",
        text: """
        Welcome to NotchPrompter.

        This text scrolls right under your camera, so you can read while keeping eye contact.

        Press Control Option P to start or pause. A short countdown runs first.

        Control Option Left and Right change the speed. Control Option Up and Down jump back or forward.

        Move the mouse over this box to pause it. Move away to continue.

        Control Option O hides or shows the overlay.

        Open the editor from the menu bar to write your own scripts, import a text or markdown file, or paste from the clipboard.

        The overlay is excluded from screen sharing, so the people you are talking to won't see it.

        Good luck with your recording!
        """
    )
}
