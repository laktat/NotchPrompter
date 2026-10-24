import AppKit
import Observation

/// Wires the stores, the scroll engine, the overlay, the listeners and the hotkeys together.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    let settings: SettingsStore
    let scripts: ScriptStore
    let engine: ScrollEngine
    let overlay: OverlayController
    let voice: VoiceDetector
    let tracker: SpeechTracker
    /// Settings → "Test microphone / recognition": listens without playing.
    var isTestingMic = false
    @ObservationIgnored private let hotkeys = HotkeyManager()
    @ObservationIgnored private var loadedScriptID: UUID?
    @ObservationIgnored private var lastMode: ScrollMode?
    @ObservationIgnored private var isOfferingDownload = false

    private init() {
        settings = SettingsStore()
        scripts = ScriptStore()
        engine = ScrollEngine(settings: settings)
        voice = VoiceDetector(settings: settings)
        tracker = SpeechTracker(settings: settings)
        overlay = OverlayController(settings: settings, scripts: scripts, engine: engine, tracker: tracker)
        hotkeys.register(app: self)

        observe { [scripts] in
            (id: scripts.selected?.id, text: scripts.selected?.text ?? "")
        } apply: { [weak self] script in
            self?.syncScript(id: script.id, text: script.text)
        }

        observe { [weak self] in
            self.map { (mode: $0.settings.settings.mode, active: $0.engine.state == .playing || $0.engine.isCountingDown,
                        testing: $0.isTestingMic) }
        } apply: { [weak self] value in
            guard let value else { return }
            self?.syncListeners(mode: value.mode, active: value.active, testing: value.testing)
        }

        observe { [settings, voice] in
            settings.settings.mode != .voice || !voice.isUsable || voice.isSpeaking
        } apply: { [engine] gateOpen in
            engine.isVoiceGateOpen = gateOpen
        }

        observe { [weak self] in
            self?.followTarget()
        } apply: { [engine] target in
            engine.followTarget = target
        }

        // Pressing play without the language's speech model: offer the download right away.
        observe { [tracker] in
            tracker.status == .needsModel
        } apply: { [weak self] needsModel in
            if needsModel { self?.offerModelDownload() }
        }

        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.settings.flush()
                self?.scripts.flush()
            }
        }

        overlay.show()
        DebugSnapshot.runIfRequested(app: self)
    }

    // MARK: Actions (menu + hotkeys)

    func togglePlay() {
        overlay.show()
        engine.togglePlayPause()
    }

    /// Stop and rewind to the top.
    func stop() {
        engine.stop()
        tracker.reset(toWord: 0)
    }

    /// Manual scroll. In word tracking, tracking continues from the line now at the top.
    func nudge(lines: Int) {
        engine.nudge(lines: lines)
        if settings.settings.mode == .speech { resyncTracker() }
    }

    // MARK: Sync

    /// The mic runs only while it's needed (playing in a voice mode, or a settings test), so the
    /// orange recording dot isn't on all the time. Permissions are asked when a voice mode is chosen.
    private func syncListeners(mode: ScrollMode, active: Bool, testing: Bool) {
        if mode != lastMode {
            lastMode = mode
            switch mode {
            case .voice where voice.permission == .unknown:
                Task { await voice.requestPermission() }
            case .speech:
                resyncTracker()
                Task {
                    await tracker.requestPermissions()
                    await tracker.refreshModelStatus()
                    if tracker.modelStatus == .notInstalled { offerModelDownload() }
                }
            default:
                break
            }
        }

        let listening = active || testing
        if mode == .voice, listening { voice.start() } else { voice.stop() }
        if mode == .speech, listening { tracker.start() } else { tracker.stop() }
    }

    /// Keeps word count and tracking current; switching scripts rewinds to the top.
    private func syncScript(id: UUID?, text: String) {
        engine.load(text: text)
        tracker.load(text: text)
        if id != loadedScriptID {
            loadedScriptID = id
            stop()
        }
    }

    // MARK: Word tracking

    /// Asks whether to download a missing on-device speech model (a one-time macOS download).
    func offerModelDownload() {
        guard !isOfferingDownload else { return }
        if case .downloading = tracker.modelStatus { return }
        isOfferingDownload = true
        // Off the observation callback, so the modal alert doesn't run inside it.
        DispatchQueue.main.async { [self] in
            defer { isOfferingDownload = false }
            let name = tracker.languageName
            let alert = NSAlert()
            alert.messageText = "Download the \(name) speech model?"
            alert.informativeText = "Word tracking recognizes your speech entirely on this Mac. For \(name), macOS "
                + "first needs to download Apple's on-device speech model, once, the same way it adds a dictation "
                + "language. Until then the text scrolls at fixed speed."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Not Now")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn {
                Task { await tracker.downloadModel() }
            }
        }
    }

    /// Scroll so the line with the next word to read sits at the top, right under the camera.
    private func followTarget() -> CGFloat? {
        let tokens = tracker.tokens
        guard settings.settings.mode == .speech, tracker.isUsable, !tokens.isEmpty, !engine.textLines.isEmpty else {
            return nil
        }
        let next = tokens[min(max(tracker.currentWord + 1, 0), tokens.count - 1)]
        return engine.textLines.top(ofCharacterAt: next.utf16Range.location)
    }

    /// Continue tracking from the line now at the top (after a manual scroll or a mode switch).
    private func resyncTracker() {
        let start = engine.textLines.lineStart(atOrBelow: engine.offset)
        tracker.reset(toWord: tracker.tokens.firstIndex { $0.utf16Range.location >= start } ?? 0)
    }
}
