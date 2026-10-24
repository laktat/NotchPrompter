import Foundation
import UniformTypeIdentifiers

/// Turns .txt / .md files into plain prompter text.
enum ScriptImporter {
    static let markdownType = UTType(filenameExtension: "md") ?? .plainText
    static let allowedTypes: [UTType] = [.plainText, .text, markdownType]

    static func load(_ url: URL) -> (title: String, text: String)? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let raw = (try? String(contentsOf: url, encoding: .utf8)).map(normalizeLineEndings) else { return nil }
        let isMarkdown = ["md", "markdown"].contains(url.pathExtension.lowercased())
        let text = isMarkdown ? stripMarkdown(raw) : raw
        return (url.deletingPathExtension().lastPathComponent, text)
    }

    /// Windows (CRLF) and old Mac (CR) line endings → "\n".
    static func normalizeLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    /// First non-empty line, shortened, as a script title.
    static func title(for text: String, fallback: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        guard !line.isEmpty else { return fallback }
        return line.count > 40 ? String(line.prefix(40)) + "…" : line
    }

    /// Removes the markdown syntax a reader shouldn't see: headings, emphasis, links, code fences, list bullets.
    static func stripMarkdown(_ markdown: String) -> String {
        var lines: [String] = []
        for var line in markdown.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { continue }
            line = line.replacingOccurrences(of: #"^\s{0,3}#{1,6}\s+"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"^\s{0,3}>\s?"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"^\s*([-*+]|\d+\.)\s+"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            line = line.replacingOccurrences(of: #"(\*\*|__|\*|_|`|~~)"#, with: "", options: .regularExpression)
            if line.trimmingCharacters(in: .whitespaces).range(of: #"^([-*_]\s*){3,}$"#, options: .regularExpression) != nil {
                line = ""
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
