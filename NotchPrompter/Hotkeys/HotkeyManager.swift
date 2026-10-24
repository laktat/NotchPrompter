import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    // ⌃⌥Space is the system "next input source" shortcut, so play/pause uses ⌃⌥P.
    static let togglePlay = Self("togglePlay", default: .init(.p, modifiers: [.control, .option]))
    static let speedUp = Self("speedUp", default: .init(.rightArrow, modifiers: [.control, .option]))
    static let speedDown = Self("speedDown", default: .init(.leftArrow, modifiers: [.control, .option]))
    static let scrollBack = Self("scrollBack", default: .init(.upArrow, modifiers: [.control, .option]))
    static let scrollForward = Self("scrollForward", default: .init(.downArrow, modifiers: [.control, .option]))
    static let toggleOverlay = Self("toggleOverlay", default: .init(.o, modifiers: [.control, .option]))
    static let rewind = Self("rewind", default: .init(.r, modifiers: [.control, .option]))
}

/// Global hotkeys (Carbon hot keys under the hood: no Accessibility permission needed).
@MainActor
final class HotkeyManager {
    static let speedStep: Double = 10

    struct Entry: Identifiable {
        let name: KeyboardShortcuts.Name
        let title: String
        var id: String { name.rawValue }
    }

    static let entries: [Entry] = [
        Entry(name: .togglePlay, title: "Play / pause"),
        Entry(name: .speedUp, title: "Speed up"),
        Entry(name: .speedDown, title: "Slow down"),
        Entry(name: .scrollBack, title: "Scroll back"),
        Entry(name: .scrollForward, title: "Scroll forward"),
        Entry(name: .rewind, title: "Stop & rewind"),
        Entry(name: .toggleOverlay, title: "Show / hide overlay"),
    ]

    func register(app: AppState) {
        KeyboardShortcuts.onKeyDown(for: .togglePlay) { [weak app] in app?.togglePlay() }
        KeyboardShortcuts.onKeyDown(for: .speedUp) { [weak app] in app?.settings.adjustSpeed(by: Self.speedStep) }
        KeyboardShortcuts.onKeyDown(for: .speedDown) { [weak app] in app?.settings.adjustSpeed(by: -Self.speedStep) }
        KeyboardShortcuts.onKeyDown(for: .scrollBack) { [weak app] in app?.nudge(lines: -1) }
        KeyboardShortcuts.onKeyDown(for: .scrollForward) { [weak app] in app?.nudge(lines: 1) }
        KeyboardShortcuts.onKeyDown(for: .rewind) { [weak app] in app?.stop() }
        KeyboardShortcuts.onKeyDown(for: .toggleOverlay) { [weak app] in app?.overlay.toggle() }
    }
}
