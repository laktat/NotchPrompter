import AppKit
import QuartzCore
import Observation

/// Drives the scroll offset. Speed is words-per-minute, converted to points/second
/// from the measured text height, so it stays right for any font size or width.
@MainActor
@Observable
final class ScrollEngine {
    enum State: Equatable {
        case idle
        case countdown(Int)
        case playing
        case paused
    }

    private(set) var state: State = .idle
    private(set) var offset: CGFloat = 0
    private(set) var isAtEnd = false

    /// Set by the overlay while the cursor is over it.
    var isHoverPaused = false
    /// Set by the voice detector; always open in fixed-speed mode.
    var isVoiceGateOpen = true

    /// Height of the laid-out script text, reported by the view.
    var contentHeight: CGFloat = 0 {
        didSet { clampOffset() }
    }
    /// Line positions of the laid-out script, reported by the view (used by word tracking).
    var textLines = TextLineMap.empty

    /// Word tracking: the offset to ease towards instead of scrolling at the wpm speed.
    var followTarget: CGFloat?

    private(set) var wordCount = 0

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    /// Fraction of full speed currently applied (0…1).
    @ObservationIgnored private var velocity: CGFloat = 0
    /// Time constant of the speed ease-in/out.
    private static let rampTime: CFTimeInterval = 0.2
    /// Time constant for gliding to the line of the word you're reading.
    private static let followTime: CFTimeInterval = 0.3

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var isMoving: Bool { state == .playing && !isHoverPaused && isVoiceGateOpen }

    var isCountingDown: Bool {
        if case .countdown = state { return true }
        return false
    }

    /// Height of one line, used for manual nudges and the end stop.
    var lineHeight: CGFloat {
        CGFloat(settings.settings.fontSize) * 1.2 + CGFloat(settings.settings.lineSpacing)
    }

    var pointsPerSecond: CGFloat {
        guard wordCount > 0, contentHeight > 0 else { return 0 }
        let wordsPerSecond = settings.settings.wordsPerMinute / 60
        return CGFloat(wordsPerSecond) * contentHeight / CGFloat(wordCount)
    }

    /// Stop once the last line reaches the reading position at the top.
    private var maxOffset: CGFloat { max(0, contentHeight - lineHeight) }

    // MARK: Script

    func load(text: String) {
        wordCount = Script.words(in: text).count
    }

    // MARK: Transport

    func togglePlayPause() {
        switch state {
        case .idle: start()
        case .countdown: stop()
        case .playing: pause()
        case .paused: isAtEnd ? start() : resume()
        }
    }

    func start() {
        cancelCountdown()
        if isAtEnd { rewind() }
        let seconds = settings.settings.countdownSeconds
        guard settings.settings.countdownEnabled, seconds > 0 else {
            play()
            return
        }
        countdownTask = Task { [weak self] in
            for n in stride(from: seconds, to: 0, by: -1) {
                self?.state = .countdown(n)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self?.play()
        }
    }

    func pause() {
        cancelCountdown()
        guard state == .playing else { return }
        state = .paused
        stopDisplayLink()
    }

    func resume() {
        guard state == .paused else { return }
        play()
    }

    /// Stop and go back to the top.
    func stop() {
        cancelCountdown()
        stopDisplayLink()
        state = .idle
        rewind()
    }

    /// Jump to an offset (clamped), e.g. to show a given line.
    func scroll(to newOffset: CGFloat) {
        offset = newOffset
        clampOffset()
    }

    func nudge(lines: Int) {
        offset += CGFloat(lines) * lineHeight * 2
        clampOffset()
        isAtEnd = offset >= maxOffset && maxOffset > 0
    }

    // MARK: Internals

    private func play() {
        countdownTask = nil
        velocity = 0
        state = .playing
        startDisplayLink()
    }

    private func rewind() {
        offset = 0
        isAtEnd = false
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        if isCountingDown { state = .idle }
    }

    private func clampOffset() {
        offset = min(max(offset, 0), maxOffset)
    }

    private func startDisplayLink() {
        stopDisplayLink()
        let proxy = DisplayLinkProxy { [weak self] link in
            MainActor.assumeIsolated { self?.tick(link) }
        }
        let screen = NotchGeometry.preferredScreen() ?? NSScreen.main
        guard let link = screen?.displayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:))) else { return }
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTimestamp = nil
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
    }

    private func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard let last = lastTimestamp else { return }
        // Clamp dt so a stall (sleep, display change) doesn't cause a jump.
        let dt = min(link.timestamp - last, 0.1)
        guard dt > 0 else { return }

        if let target = followTarget {
            guard !isHoverPaused else { return }
            let clamped = min(max(target, 0), maxOffset)
            offset += (clamped - offset) * min(1, CGFloat(dt / Self.followTime))
            return
        }

        // Ease towards full speed or a stop, so voice/hover pauses don't jerk the text.
        let target: CGFloat = isMoving ? 1 : 0
        velocity += (target - velocity) * min(1, CGFloat(dt / Self.rampTime))
        if target == 0, velocity < 0.002 { velocity = 0 }
        guard velocity > 0 else { return }

        offset += pointsPerSecond * velocity * CGFloat(dt)
        if offset >= maxOffset {
            offset = maxOffset
            isAtEnd = true
            state = .paused
            stopDisplayLink()
        }
    }
}

/// CADisplayLink retains its target; the proxy keeps the engine out of that cycle.
private final class DisplayLinkProxy: NSObject {
    private let onTick: (CADisplayLink) -> Void

    init(onTick: @escaping (CADisplayLink) -> Void) {
        self.onTick = onTick
    }

    @objc func tick(_ link: CADisplayLink) { onTick(link) }
}
