import SwiftUI

/// Development aid: `open NotchPrompter.app --args -SnapshotDir /some/dir` renders the overlay
/// off-screen (idle, countdown, scrolling, nudged, word-tracking highlight) to PNGs and logs the
/// engine state. Needs no Screen Recording permission and never starts the microphone.
@MainActor
enum DebugSnapshot {
    static func runIfRequested(app: AppState) {
        guard let dir = UserDefaults.standard.string(forKey: "SnapshotDir") else { return }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        var log = ""

        func write(_ line: String) {
            log += line + "\n"
            try? log.write(to: url.appendingPathComponent("state.txt"), atomically: true, encoding: .utf8)
        }

        func render(_ view: some View, _ name: String) {
            let renderer = ImageRenderer(content: view.background(Color(white: 0.85)))
            renderer.scale = 2
            if let image = renderer.nsImage,
               let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: url.appendingPathComponent("\(name).png"))
            }
        }

        func snap(_ name: String) {
            render(OverlayView(settings: app.settings, scripts: app.scripts,
                               engine: app.engine, tracker: app.tracker, overlay: app.overlay), name)
            let e = app.engine
            write("\(name): state=\(e.state) offset=\(e.offset) content=\(e.contentHeight) words=\(e.wordCount) "
                  + "pts/s=\(e.pointsPerSecond) hoverPaused=\(e.isHoverPaused)")
        }

        /// Highlights `word` and scrolls its line to the top exactly as word tracking does.
        func snapTracking(word: Int, _ name: String) {
            let text = app.scripts.selected?.text ?? ""
            let s = app.settings.settings
            let tokens = app.tracker.tokens
            guard tokens.indices.contains(word) else { return write("\(name): script too short") }
            let top = app.engine.textLines.top(ofCharacterAt: tokens[word].utf16Range.location)
            app.engine.scroll(to: top)
            let width = app.overlay.geometry.map { OverlayLayout(settings: s, geometry: $0).textWidth } ?? 400
            render(ScrollingTextView(text: text, settings: s, engine: app.engine,
                                     highlight: WordHighlight(current: tokens[word].utf16Range))
                .frame(width: width, height: s.height)
                .background(Color.black), name)
            write("lines: " + app.engine.textLines.lines.map { "\($0.start)@\(Int($0.top))" }.joined(separator: " "))
            write("\(name): word \(word) “\(text[tokens[word].range])” lineTop=\(top) lines=\(app.engine.textLines.lines.count) "
                  + "contentHeight=\(app.engine.contentHeight)")
        }

        Task {
            try? await Task.sleep(for: .seconds(0.8))
            snap("1-idle")
            app.togglePlay()
            try? await Task.sleep(for: .seconds(1.5))
            snap("2-countdown")
            try? await Task.sleep(for: .seconds(6))
            snap("3-scrolling")
            app.engine.nudge(lines: 3)
            try? await Task.sleep(for: .seconds(0.3))
            snap("4-nudged")
            app.stop()
            try? await Task.sleep(for: .seconds(0.3))
            snapTracking(word: 40, "5-tracking-word40")
            snapTracking(word: 87, "6-tracking-word87")
            app.stop()

            // `-TrackerTestFile x.wav -TrackerTestScript "…" -TrackerTestLanguage en-US`:
            // the real recognizer + matcher, fed from a file instead of the microphone.
            let defaults = UserDefaults.standard
            if let file = defaults.string(forKey: "TrackerTestFile"),
               let script = defaults.string(forKey: "TrackerTestScript") {
                let selected = app.scripts.selected?.text ?? ""
                app.tracker.load(text: script)
                app.tracker.reset(toWord: 0)
                let started = Date()
                let positions = await app.tracker.debugRun(file: URL(fileURLWithPath: file),
                                                           languageID: defaults.string(forKey: "TrackerTestLanguage") ?? "en-US")
                write("tracker test (\(app.tracker.tokens.count) words, \(String(format: "%.1f", Date().timeIntervalSince(started))) s): "
                      + positions.joined(separator: " ") + " | heard: \(app.tracker.heard)")
                app.tracker.load(text: selected)
                app.tracker.reset(toWord: 0)
            }
            write("done")
        }
    }
}
