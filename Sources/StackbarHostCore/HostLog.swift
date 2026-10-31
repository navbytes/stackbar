import Foundation
import StackbarProtocol

/// The host's own log file: one line per entry, timestamped, tagged with the
/// plugin it came from. It rolls over to `<name>.1` at `maxBytes`, so it never
/// grows past about twice that. Writes are serialized and never throw: a log
/// that cannot be written must not take the host down.
public final class HostLog: @unchecked Sendable {
    public let file: URL
    public let maxBytes: Int
    private let lock = NSLock()
    private var handle: FileHandle?
    private var size = 0
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init(file: URL, maxBytes: Int = 5 * 1024 * 1024) {
        self.file = file
        self.maxBytes = maxBytes
    }

    /// `StackbarPaths.logFile`, shared by the app and `stackbarctl`.
    public static let shared = HostLog(file: StackbarPaths.logFile)

    public var rolledFile: URL { file.appendingPathExtension("1") }

    public func write(_ level: LogLevel, _ message: String, plugin: String? = nil, now: Date = Date()) {
        let tag = plugin.map { " [\($0)]" } ?? ""
        // One entry per line: newlines inside a message are escaped.
        let body = message.replacingOccurrences(of: "\n", with: "\\n")
        let line = "\(formatter.string(from: now)) \(level.rawValue.uppercased())\(tag) \(body)\n"
        let data = Data(line.utf8)
        lock.lock()
        defer { lock.unlock() }
        if size + data.count > maxBytes { roll() }
        guard let handle = openIfNeeded() else { return }
        do {
            try handle.write(contentsOf: data)
            size += data.count
        } catch {
            self.handle = nil
        }
    }

    /// The last `count` lines, oldest first, across the rolled file too.
    public func tail(_ count: Int) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        var lines: [String] = []
        for url in [rolledFile, file] {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            lines += text.split(separator: "\n").map(String.init)
        }
        return Array(lines.suffix(count))
    }

    private func openIfNeeded() -> FileHandle? {
        if let handle { return handle }
        let manager = FileManager.default
        try? manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !manager.fileExists(atPath: file.path) {
            manager.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let opened = try? FileHandle(forWritingTo: file) else { return nil }
        size = Int((try? opened.seekToEnd()) ?? 0)
        handle = opened
        return opened
    }

    private func roll() {
        try? handle?.close()
        handle = nil
        let manager = FileManager.default
        try? manager.removeItem(at: rolledFile)
        try? manager.moveItem(at: file, to: rolledFile)
        size = 0
    }
}
