import AppKit
import SwiftUI
import Observation

/// Borderless, non-activating, click-through panel that sits over the notch.
final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Must come before `level`: setting isFloatingPanel resets the level to .floating.
        isFloatingPanel = true
        // Above the menu bar (and the notch area it owns), also above fullscreen apps.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Exclude from screenshots, screen recording and screen sharing.
        // `defaults write com.matejlakomy.NotchPrompter AllowScreenCapture -bool YES` turns this
        // off, for checking the layout in screenshots and comparing capture behaviour.
        sharingType = UserDefaults.standard.bool(forKey: "AllowScreenCapture") ? .readOnly : .none
        ignoresMouseEvents = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Keep AppKit from pushing the window below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Owns the panel: positioning, visibility, and the hover-to-pause check.
@MainActor
@Observable
final class OverlayController {
    private(set) var isVisible = false
    private(set) var geometry: NotchGeometry?

    @ObservationIgnored private let panel = OverlayPanel()
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let engine: ScrollEngine
    @ObservationIgnored private var hoverTimer: Timer?

    init(settings: SettingsStore, scripts: ScriptStore, engine: ScrollEngine, tracker: SpeechTracker) {
        self.settings = settings
        self.engine = engine

        let content = OverlayView(settings: settings, scripts: scripts, engine: engine, tracker: tracker, overlay: self)
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        panel.contentView = host

        refreshGeometry()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshGeometry() }
        }
        observe { [weak self] in
            self?.targetFrame()
        } apply: { [weak self] frame in
            guard let self, let frame, panel.frame != frame else { return }
            panel.setFrame(frame, display: true)
        }
    }

    func show() {
        guard !isVisible else { return }
        refreshGeometry()
        if let frame = targetFrame() { panel.setFrame(frame, display: true) }
        panel.orderFrontRegardless()
        isVisible = true
        startHoverTracking()
    }

    func hide() {
        guard isVisible else { return }
        panel.orderOut(nil)
        isVisible = false
        stopHoverTracking()
        engine.isHoverPaused = false
    }

    func toggle() { isVisible ? hide() : show() }

    private func refreshGeometry() {
        geometry = NotchGeometry.preferredScreen().map(NotchGeometry.init(screen:))
    }

    /// Where the panel should be for the current settings and screen.
    private func targetFrame() -> CGRect? {
        guard let geometry else { return nil }
        return OverlayLayout(settings: settings.settings, geometry: geometry).frame(in: geometry)
    }

    // MARK: Hover

    // The panel ignores mouse events (click-through), so it can't get tracking-area
    // callbacks. Polling the cursor position is cheap and needs no permissions.
    private func startHoverTracking() {
        stopHoverTracking()
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func stopHoverTracking() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    private func updateHover() {
        // Only the visible body counts, not the transparent flare corners.
        let body = panel.frame.insetBy(dx: OverlayLayout.flare, dy: 0)
        let inside = body.contains(NSEvent.mouseLocation)
        if engine.isHoverPaused != inside {
            engine.isHoverPaused = inside
        }
    }
}
