import SwiftUI

/// Script list on the left, plain-text editor on the right.
struct EditorView: View {
    let app: AppState
    @State private var importing = false
    @State private var pendingDelete: Script?
    @State private var clipboardEmpty = false

    private var scripts: ScriptStore { app.scripts }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { scripts.selectedID }, set: { scripts.selectedID = $0 })) {
                ForEach(scripts.scripts) { script in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(script.title.isEmpty ? "Untitled" : script.title)
                            .lineLimit(1)
                        Text("\(script.wordCount) words · \(script.duration(atWPM: app.settings.settings.wordsPerMinute))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(Optional(script.id))
                    .contextMenu {
                        Button("Delete", role: .destructive) { pendingDelete = script }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .onDeleteCommand { pendingDelete = scripts.selected }
        } detail: {
            if let script = scripts.selected {
                ScriptDetailView(store: scripts, scriptID: script.id, wpm: app.settings.settings.wordsPerMinute)
            } else {
                ContentUnavailableView("No Script", systemImage: "text.alignleft",
                                       description: Text("Create a new script, import a file, or paste from the clipboard."))
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { scripts.add() } label: { Label("New Script", systemImage: "square.and.pencil") }
                    .help("New script")
                Button {
                    clipboardEmpty = !scripts.addFromClipboard()
                } label: { Label("Paste from Clipboard", systemImage: "doc.on.clipboard") }
                    .help("New script from clipboard")
                Button { importing = true } label: { Label("Import", systemImage: "square.and.arrow.down") }
                    .help("Import .txt or .md")
                Button { pendingDelete = scripts.selected } label: { Label("Delete", systemImage: "trash") }
                    .help("Delete script")
                    .disabled(scripts.selected == nil)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: ScriptImporter.allowedTypes,
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { scripts.importFiles(urls) }
        }
        .confirmationDialog("Delete “\(pendingDelete?.title ?? "")”?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { scripts.delete(pendingDelete.id) }
                pendingDelete = nil
            }
        }
        .alert("The clipboard has no text.", isPresented: $clipboardEmpty) {}
        .frame(minWidth: 640, minHeight: 400)
    }
}

private struct ScriptDetailView: View {
    let store: ScriptStore
    let scriptID: UUID
    let wpm: Double

    var body: some View {
        let script = store.script(scriptID)
        VStack(spacing: 0) {
            TextField("Title", text: Binding(get: { script?.title ?? "" },
                                             set: { store.update(scriptID, title: $0) }))
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Divider()
            TextEditor(text: Binding(get: { script?.text ?? "" },
                                     set: { store.update(scriptID, text: $0) }))
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(12)
            Divider()
            HStack {
                Text("\(script?.wordCount ?? 0) words")
                Spacer()
                Text("≈ \(script?.duration(atWPM: wpm) ?? "0:00") at \(Int(wpm)) wpm")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
