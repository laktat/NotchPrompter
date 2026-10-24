import SwiftUI

@main
struct NotchPrompterApp: App {
    private let app = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(app: app)
        } label: {
            Image(systemName: app.engine.state == .playing ? "play.rectangle.fill" : "text.aligncenter")
        }
        .menuBarExtraStyle(.menu)

        Window("Scripts", id: "editor") {
            EditorView(app: app)
        }
        .defaultSize(width: 820, height: 540)

        Window("NotchPrompter Settings", id: "settings") {
            SettingsView(app: app)
        }
        .windowResizability(.contentSize)
    }
}
