import AppKit
import Observation

@MainActor
@Observable
final class ScriptStore {
    private static let fileName = "scripts.json"

    private struct Library: Codable {
        var scripts: [Script]
        var selectedID: UUID?
    }

    private(set) var scripts: [Script]
    var selectedID: UUID? {
        didSet { if selectedID != oldValue { scheduleSave() } }
    }

    var selected: Script? { scripts.first { $0.id == selectedID } }

    @ObservationIgnored private let saver = Debouncer(delay: 0.5)

    init() {
        let library = Persistence.load(Library.self, from: Self.fileName)
        scripts = library?.scripts ?? [Script.welcome]
        selectedID = library?.selectedID ?? scripts.first?.id
        if selected == nil { selectedID = scripts.first?.id }
    }

    func script(_ id: UUID) -> Script? { scripts.first { $0.id == id } }

    @discardableResult
    func add(title: String = "Untitled", text: String = "") -> Script {
        let script = Script(title: title, text: text)
        scripts.insert(script, at: 0)
        selectedID = script.id
        scheduleSave()
        return script
    }

    func update(_ id: UUID, title: String? = nil, text: String? = nil) {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        if let title { scripts[index].title = title }
        if let text { scripts[index].text = text }
        scripts[index].modified = Date()
        scheduleSave()
    }

    func delete(_ id: UUID) {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        scripts.remove(at: index)
        if selectedID == id {
            selectedID = scripts.indices.contains(index) ? scripts[index].id : scripts.last?.id
        }
        scheduleSave()
    }

    /// Creates a script from the clipboard text. Returns false when the clipboard has no text.
    @discardableResult
    func addFromClipboard() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string).map(ScriptImporter.normalizeLineEndings),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        add(title: ScriptImporter.title(for: text, fallback: "Pasted script"), text: text)
        return true
    }

    func importFiles(_ urls: [URL]) {
        for url in urls {
            if let script = ScriptImporter.load(url) {
                add(title: script.title, text: script.text)
            }
        }
    }

    func flush() { saver.flush() }

    private func scheduleSave() {
        saver.schedule { [weak self] in
            guard let self else { return }
            Persistence.save(Library(scripts: scripts, selectedID: selectedID), to: Self.fileName)
        }
    }
}
