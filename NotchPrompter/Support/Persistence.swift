import Foundation

/// Reads and writes small JSON files in ~/Library/Application Support/NotchPrompter.
enum Persistence {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("NotchPrompter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let url = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder.iso.decode(T.self, from: data)
        } catch {
            NSLog("NotchPrompter: could not decode \(name): \(error)")
            return nil
        }
    }

    static func writeText(_ text: String, to name: String) {
        try? text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        let url = directory.appendingPathComponent(name)
        do {
            let data = try JSONEncoder.iso.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("NotchPrompter: could not save \(name): \(error)")
        }
    }
}

private extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

private extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

/// Coalesces bursts of changes (e.g. typing) into a single save.
@MainActor
final class Debouncer {
    private let delay: TimeInterval
    private var work: DispatchWorkItem?

    init(delay: TimeInterval) { self.delay = delay }

    func schedule(_ action: @escaping () -> Void) {
        work?.cancel()
        let item = DispatchWorkItem(block: action)
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func flush() {
        guard let work, !work.isCancelled else { return }
        work.perform()
        work.cancel()
        self.work = nil
    }
}
