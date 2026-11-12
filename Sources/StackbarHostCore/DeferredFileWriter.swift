import Foundation

/// Writes a small JSON file off the caller's thread. Writes made while one
/// is waiting are folded into the newest: only the last snapshot is encoded
/// and written, so a burst of changes costs one write.
///
/// The palette records a use and a pick on every Return, on the main actor;
/// encoding and an atomic write there delayed what happens right after it.
final class DeferredFileWriter: @unchecked Sendable {
    private let file: URL
    private let queue = DispatchQueue(label: "stackbar.deferred-file-writer", qos: .utility)
    private let lock = NSLock()
    private var latest: (@Sendable () -> Data?)?
    private var queued = false

    init(file: URL) {
        self.file = file
    }

    /// Writes what `encode` makes, soon. `encode` runs on the writer's queue
    /// and must hold a snapshot, not the live state.
    func write(_ encode: @escaping @Sendable () -> Data?) {
        let start = lock.withLock { () -> Bool in
            latest = encode
            guard !queued else { return false }
            queued = true
            return true
        }
        if start { queue.async { [self] in drain() } }
    }

    /// Returns once everything handed to `write` so far is on disk.
    func flush() {
        queue.sync {}
    }

    private func drain() {
        let encode = lock.withLock { () -> (@Sendable () -> Data?)? in
            queued = false
            defer { latest = nil }
            return latest
        }
        guard let data = encode?() else { return }
        try? JSONFile.write(data, to: file)
    }
}
