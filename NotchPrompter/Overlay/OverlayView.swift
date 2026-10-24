import SwiftUI

/// The black "grown notch" with the scrolling script inside.
struct OverlayView: View {
    let settings: SettingsStore
    let scripts: ScriptStore
    let engine: ScrollEngine
    let tracker: SpeechTracker
    let overlay: OverlayController

    private var isTracking: Bool { settings.settings.mode == .speech && engine.state != .idle }

    /// The word just spoken, while word tracking is running.
    private var highlight: WordHighlight? {
        guard isTracking, tracker.isUsable, tracker.tokens.indices.contains(tracker.currentWord) else { return nil }
        return WordHighlight(current: tracker.tokens[tracker.currentWord].utf16Range)
    }

    /// Shown at the bottom of the overlay so a word-tracking problem can't go unnoticed.
    private var trackingProblem: String? {
        guard settings.settings.mode == .speech else { return nil }
        if case .downloading = tracker.modelStatus { return tracker.problem }
        return engine.state == .idle ? nil : tracker.problem
    }

    var body: some View {
        if let geometry = overlay.geometry {
            content(layout: OverlayLayout(settings: settings.settings, geometry: geometry))
        }
    }

    private func content(layout: OverlayLayout) -> some View {
        let s = settings.settings
        return ZStack(alignment: .top) {
            NotchShape(topRadius: OverlayLayout.flare, bottomRadius: OverlayLayout.bottomRadius)
                .fill(Color.black.opacity(s.backgroundOpacity))

            VStack(spacing: 0) {
                Color.clear.frame(height: layout.topInset)
                ZStack {
                    ScrollingTextView(text: scripts.selected?.text ?? "",
                                      settings: s,
                                      engine: engine,
                                      highlight: highlight)
                        .opacity(engine.isCountingDown ? 0.25 : 1)
                    CountdownBadge(engine: engine)
                }
                .frame(width: layout.textWidth, height: layout.textHeight)
                .overlay(alignment: .bottom) {
                    if let problem = trackingProblem {
                        TrackingCaption(text: problem)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    StatusBadge(engine: engine, trackingUnavailable: isTracking && !tracker.isUsable)
                        .offset(x: OverlayLayout.horizontalPadding - 6, y: 2)
                }
            }
        }
        .frame(width: layout.windowWidth, height: layout.windowHeight, alignment: .top)
        .animation(.easeOut(duration: 0.15), value: engine.isCountingDown)
    }
}

private struct TrackingCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(white: 0.22), in: Capsule())
            .padding(.bottom, 4)
    }
}

private struct CountdownBadge: View {
    let engine: ScrollEngine

    var body: some View {
        if case .countdown(let n) = engine.state {
            Text("\(n)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: true))
                .id(n)
        }
    }
}

/// Small glyph so it's obvious why the text stopped: paused, finished, or waiting for your voice.
private struct StatusBadge: View {
    let engine: ScrollEngine
    /// Word tracking was chosen but can't run, so the text scrolls at fixed speed.
    let trackingUnavailable: Bool

    var body: some View {
        if let symbol {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .padding(4)
        }
    }

    private var symbol: String? {
        if trackingUnavailable { return "exclamationmark.triangle.fill" }
        switch engine.state {
        case .paused:
            return engine.isAtEnd ? "checkmark" : "pause.fill"
        case .playing where engine.isHoverPaused:
            return "pause.fill"
        case .playing where !engine.isVoiceGateOpen:
            return "mic.fill"
        default:
            return nil
        }
    }
}
