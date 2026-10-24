import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    let app: AppState

    var body: some View {
        TabView {
            AppearanceTab(store: app.settings)
                .tabItem { Label("Appearance", systemImage: "textformat.size") }
            ScrollingTab(app: app, store: app.settings)
                .tabItem { Label("Scrolling", systemImage: "arrow.up.and.down.text.horizontal") }
            HotkeysTab()
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 8)
    }
}

private struct AppearanceTab: View {
    @Bindable var store: SettingsStore

    var body: some View {
        Form {
            LabeledSlider("Width", value: $store.settings.width, in: 280...900, step: 10, unit: "pt")
            LabeledSlider("Height", value: $store.settings.height, in: 50...400, step: 5, unit: "pt")
            LabeledSlider("Font size", value: $store.settings.fontSize, in: 12...64, step: 1, unit: "pt")
            LabeledSlider("Line spacing", value: $store.settings.lineSpacing, in: 0...20, step: 1, unit: "pt")
            ColorPicker("Text color", selection: Binding(get: { store.settings.textColor.color },
                                                         set: { store.settings.textColor = RGBAColor($0) }))
            LabeledSlider("Background opacity", value: $store.settings.backgroundOpacity, in: 0.2...1, step: 0.05,
                          format: { "\(Int(($0 * 100).rounded()))%" })
            Button("Restore Defaults") {
                let d = PrompterSettings()
                store.settings.width = d.width
                store.settings.height = d.height
                store.settings.fontSize = d.fontSize
                store.settings.lineSpacing = d.lineSpacing
                store.settings.textColor = d.textColor
                store.settings.backgroundOpacity = d.backgroundOpacity
            }
        }
        .formStyle(.grouped)
    }
}

private struct ScrollingTab: View {
    let app: AppState
    @Bindable var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $store.settings.mode) {
                    ForEach(ScrollMode.available) { Text($0.title).tag($0) }
                }
                LabeledSlider("Speed", value: $store.settings.wordsPerMinute, in: PrompterSettings.wpmRange, step: 5,
                              format: { "\(Int($0)) wpm" })
                Toggle("Countdown before start", isOn: $store.settings.countdownEnabled)
                Stepper("Countdown: \(store.settings.countdownSeconds) s",
                        value: $store.settings.countdownSeconds, in: 1...10)
                    .disabled(!store.settings.countdownEnabled)
            } footer: {
                Text("Hover the mouse over the overlay to pause scrolling.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch store.settings.mode {
            case .voice: VoiceSection(app: app, store: store)
            case .speech: WordTrackingSection(app: app, store: store)
            case .fixed: EmptyView()
            }
        }
        .formStyle(.grouped)
        .onDisappear { app.isTestingMic = false }
    }
}

private struct VoiceSection: View {
    @Bindable var app: AppState
    @Bindable var store: SettingsStore

    private var voice: VoiceDetector { app.voice }

    var body: some View {
        Section {
            LabeledSlider("Sensitivity", value: $store.settings.voiceSensitivity, in: 0...1, step: 0.05,
                          format: { "+\(Int(SpeechGate.margin(forSensitivity: $0).rounded())) dB" })
            LabeledContent("Input level") {
                HStack {
                    LevelMeter(level: voice.level, threshold: voice.thresholdDB,
                               speaking: voice.isSpeaking, active: voice.isRunning)
                    Text(voice.isRunning ? String(format: "%.0f dB", voice.level) : "off")
                        .monospacedDigit()
                        .frame(width: 64, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle("Test microphone", isOn: $app.isTestingMic)
                .disabled(voice.permission == .denied)
        } header: {
            Text("Voice activation")
        } footer: {
            footer
        }
    }

    @ViewBuilder private var footer: some View {
        if voice.permission == .denied {
            HStack {
                Text("Microphone access is off, so the text scrolls at fixed speed.")
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }
            .font(.caption)
        } else if let error = voice.errorMessage {
            Text(error).font(.caption).foregroundStyle(.red)
        } else {
            Text("Scrolls only while you speak. The app measures the background noise and treats anything clearly louder as speech; the tick on the bar is that threshold. If the bar stays grey while you talk, raise sensitivity; if noise turns it green, lower it. Headphones keep other people's voices from moving the text.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WordTrackingSection: View {
    @Bindable var app: AppState
    @Bindable var store: SettingsStore

    private var tracker: SpeechTracker { app.tracker }

    var body: some View {
        Section {
            Picker("Language", selection: $store.settings.speechLocale) {
                ForEach(SpeechTracker.languages, id: \.id) { Text($0.name).tag($0.id) }
            }
            .disabled(app.isTestingMic || app.engine.state != .idle)
            LabeledContent("Speech model") { modelStatus }
            Toggle("Test recognition", isOn: $app.isTestingMic)
                .disabled(tracker.modelStatus != .installed)
            if app.isTestingMic {
                LabeledContent("Heard") {
                    Text(tracker.heard.isEmpty ? "Say something…" : tracker.heard)
                        .foregroundStyle(tracker.heard.isEmpty ? .secondary : .primary)
                        .lineLimit(2)
                }
            }
        } header: {
            Text("Word tracking")
        } footer: {
            footer
        }
        .task(id: store.settings.speechLocale) { await tracker.refreshModelStatus() }
    }

    @ViewBuilder private var modelStatus: some View {
        switch tracker.modelStatus {
        case .unknown:
            ProgressView().controlSize(.small)
        case .installed:
            Label("Installed, on-device", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .notInstalled:
            Button("Download") { Task { await tracker.downloadModel() } }
        case .downloading(let fraction):
            ProgressView(value: fraction)
                .frame(width: 140)
        case .unsupported(let message):
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder private var footer: some View {
        if case .unavailable(let message) = tracker.status {
            Text(message).font(.caption).foregroundStyle(.red)
        } else {
            Text("The text follows the words you say and highlights the current one. Recognition runs entirely on this Mac. A missing language model is downloaded once by macOS, the same way as a dictation language. Use Control Option Up/Down to jump if you go off-script; tracking continues from there.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Horizontal level bar (-80…0 dBFS) with a tick at the speaking threshold.
private struct LevelMeter: View {
    let level: Double
    let threshold: Double
    let speaking: Bool
    let active: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(speaking ? Color.green : Color.secondary)
                    .frame(width: w * fraction(level))
                    .animation(.linear(duration: 0.05), value: level)
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 2)
                    .offset(x: w * fraction(threshold) - 1)
            }
        }
        .frame(height: 8)
        .opacity(active ? 1 : 0.4)
        .frame(minWidth: 160)
    }

    private func fraction(_ db: Double) -> CGFloat {
        CGFloat(min(max((db - VoiceDetector.floorDB) / -VoiceDetector.floorDB, 0), 1))
    }
}

private struct HotkeysTab: View {
    var body: some View {
        Form {
            ForEach(HotkeyManager.entries) { entry in
                KeyboardShortcuts.Recorder(entry.title, name: entry.name)
            }
            Text("Hotkeys work in any app. Click a field and press a new combination to change it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, unit: String) {
        self.init(title, value: value, in: range, step: step, format: { "\(Int($0)) \(unit)" })
    }

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
         format: @escaping (Double) -> String) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: step)
                Text(format(value))
                    .monospacedDigit()
                    .frame(width: 64, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
