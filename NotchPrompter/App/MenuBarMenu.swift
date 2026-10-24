import SwiftUI

struct MenuBarMenu: View {
    let app: AppState
    @Environment(\.openWindow) private var openWindow

    private var engine: ScrollEngine { app.engine }

    var body: some View {
        Button(playTitle) { app.togglePlay() }
        Button("Stop & Rewind") { app.stop() }
        Button(app.overlay.isVisible ? "Hide Overlay" : "Show Overlay") { app.overlay.toggle() }

        Divider()

        Picker("Script", selection: Binding(get: { app.scripts.selectedID }, set: { app.scripts.selectedID = $0 })) {
            ForEach(app.scripts.scripts) { script in
                Text(script.title.isEmpty ? "Untitled" : script.title).tag(Optional(script.id))
            }
        }
        Picker("Mode", selection: Binding(get: { app.settings.settings.mode }, set: { app.settings.settings.mode = $0 })) {
            ForEach(ScrollMode.available) { Text($0.title).tag($0) }
        }
        Text("Speed: \(Int(app.settings.settings.wordsPerMinute)) wpm")
        if app.settings.settings.mode == .voice, !app.voice.isUsable {
            Text("⚠︎ Microphone unavailable — using fixed speed")
        }
        if app.settings.settings.mode == .speech {
            Text("Language: \(app.tracker.languageName)")
            if let problem = app.tracker.problem {
                Text("⚠︎ \(problem)")
            }
            if app.tracker.status == .needsModel || app.tracker.modelStatus == .notInstalled {
                Button("Download \(app.tracker.languageName) Speech Model…") { app.offerModelDownload() }
            }
        }

        Divider()

        Button("Open Editor…") { open("editor") }
            .keyboardShortcut("e")
        Button("Settings…") { open("settings") }
            .keyboardShortcut(",")

        Divider()

        Button("Quit NotchPrompter") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var playTitle: String {
        switch engine.state {
        case .idle: "Start"
        case .countdown: "Cancel Countdown"
        case .playing: "Pause"
        case .paused: engine.isAtEnd ? "Start Over" : "Resume"
        }
    }

    /// Menu bar apps aren't active by default, so bring the app forward with the window.
    private func open(_ id: String) {
        NSApp.activate()
        openWindow(id: id)
    }
}
