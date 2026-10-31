import Foundation

/// Polls a folder for `.swift` files being added, removed or changed. The app
/// uses it to pick up plugins as they are saved, which is what makes editing a
/// plugin (by hand or by an agent) feel live.
public final class DirectoryWatcher: @unchecked Sendable {
    public struct Change: Equatable, Sendable {
        public var added: [URL]
        public var removed: [URL]
        public var modified: [URL]
        public var isEmpty: Bool { added.isEmpty && removed.isEmpty && modified.isEmpty }
    }

    public let directory: URL
    public let fileExtension: String
    private var task: Task<Void, Never>?
    private let lock = NSLock()
    private var last: [String: String] = [:]

    public init(directory: URL, fileExtension: String = "swift") {
        self.directory = directory
        self.fileExtension = fileExtension
        self.last = scan()
    }

    deinit { task?.cancel() }

    /// Calls `onChange` (on an arbitrary thread) whenever a poll finds a change.
    public func start(every interval: Double = 1.5, onChange: @escaping @Sendable (Change) -> Void) {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard let self, !Task.isCancelled else { return }
                let change = self.poll()
                if !change.isEmpty { onChange(change) }
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// One poll, also usable directly (tests).
    public func poll() -> Change {
        let now = scan()
        let before = lock.withLock { () -> [String: String] in
            defer { last = now }
            return last
        }
        let url = { (path: String) in URL(fileURLWithPath: path) }
        return Change(
            added: now.keys.filter { before[$0] == nil }.sorted().map(url),
            removed: before.keys.filter { now[$0] == nil }.sorted().map(url),
            modified: now.keys.filter { before[$0] != nil && before[$0] != now[$0] }.sorted().map(url)
        )
    }

    private func scan() -> [String: String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        var result: [String: String] = [:]
        for file in files where file.pathExtension == fileExtension {
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            result[file.path] = "\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)-\(values?.fileSize ?? 0)"
        }
        return result
    }
}
