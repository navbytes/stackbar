import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Makes sure only one Fluid app runs per user. A second copy would rebind
/// the agent socket out from under the first and run every plugin twice
/// (two helpers sharing one storage file, two power assertions, double
/// notifications). The lock is an `flock` on a file in the data directory,
/// which the OS drops when the holder exits, even after a crash.
public final class InstanceLock: @unchecked Sendable {
    private let fd: Int32

    private init(fd: Int32) { self.fd = fd }

    /// Takes the lock, or returns nil when another process holds it.
    public static func acquire(_ file: URL) -> InstanceLock? {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(file.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return nil
        }
        return InstanceLock(fd: fd)
    }

    deinit {
        flock(fd, LOCK_UN)
        close(fd)
    }
}
