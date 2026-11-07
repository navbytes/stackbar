import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// The plugin side of the pipe: host messages on stdin, plugin messages on a
/// private copy of stdout.
///
/// At start-up the real stdout is duplicated for the protocol and file
/// descriptor 1 is pointed at stderr. A stray `print()` in plugin code then
/// lands in the host's log instead of corrupting the message stream — an easy
/// mistake to make, and the kind an AI-written plugin will make.
final class StdioTransport: Sendable {
    private let output: FileHandle
    private let lock = NSLock()
    /// Set once a message had a NaN or infinite number, which is said once.
    private nonisolated(unsafe) var warnedNonFinite = false

    init() {
        let protocolFD = dup(STDOUT_FILENO)
        dup2(STDERR_FILENO, STDOUT_FILENO)
        output = FileHandle(fileDescriptor: protocolFD, closeOnDealloc: true)
    }

    var send: PluginRuntime.Send {
        { [self] message in
            guard let (data, warning) = Self.encoded(message) else { return }
            // Flush C stdio (where `print` buffers, now pointed at stderr) so a
            // stray print reaches the log alongside the message it preceded.
            fflush(nil)
            lock.lock()
            defer { lock.unlock() }
            output.write(data)
            if let warning, !warnedNonFinite, let line = try? LineCodec.encode(warning) {
                warnedNonFinite = true
                output.write(line)
            }
        }
    }

    /// The message as a line. A NaN or infinite number (a progress of
    /// `done / total` with no total, say) would make the encoder throw and
    /// the whole render vanish, leaving the old one on screen; it is sent
    /// as 0 instead, with a warning for the log.
    static func encoded(_ message: PluginMessage) -> (Data, warning: PluginMessage?)? {
        if let data = try? LineCodec.encode(message) { return (data, nil) }
        guard let (data, replaced) = try? LineCodec.encodeReplacingNonFinite(message) else { return nil }
        let warning: PluginMessage? = replaced
            ? .log(level: .warning, message: "a view or value had a NaN or infinite number (a division by zero?); it is shown as 0")
            : nil
        return (data, warning)
    }

    /// Host messages, read on a dedicated thread so a blocking read never
    /// holds the main actor. Undecodable lines are skipped; EOF finishes the
    /// mailbox.
    func incoming() -> Mailbox {
        let mailbox = Mailbox()
        // Raw reads, not `readLine`: a thread parked in C stdio's stdin
        // would hold a lock that the `fflush(nil)` in `send` also takes.
        let send = self.send
        let reader = Thread {
            let input = FileHandle.standardInput
            // Room for `hello` with the largest storage grant: the host is
            // trusted, and a hello dropped for its size left the plugin
            // starting for good.
            var buffer = LineBuffer(maxLineBytes: Self.maxIncomingLineBytes)
            while true {
                // Each read gets its own autorelease pool: on macOS
                // `availableData` and the decoding behind it hand back
                // autoreleased objects, and this thread's outer pool
                // would only drain when the plugin exits, so memory
                // grew with every message.
                let more = withAutoreleasePool {
                    let chunk = input.availableData
                    if chunk.isEmpty { return false }
                    let dropped = buffer.droppedLines
                    Self.dispatch(buffer.append(chunk), to: mailbox)
                    if buffer.droppedLines > dropped {
                        send(.log(level: .error, message: "a message from Stackbar over \(Self.maxIncomingLineBytes / 1024 / 1024) MB was dropped"))
                    }
                    return true
                }
                if !more { break }
            }
            // The host is gone (it quit or crashed). Fail waiting host
            // calls so the runtime loop can finish, and don't outlive the
            // host even if plugin code is stuck.
            HostClient.shared.failAll("the host went away")
            mailbox.finish()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { exit(0) }
        }
        reader.start()
        return mailbox
    }

    /// Twice the largest storage quota (JSON escaping), plus room for the rest.
    static let maxIncomingLineBytes = 2 * Manifest.maxStorageMegabytes * 1024 * 1024 + LineBuffer.defaultMaxLineBytes

    private static func dispatch(_ lines: [Data], to mailbox: Mailbox) {
        for line in lines {
            guard let message = try? LineCodec.decode(HostMessage.self, from: line) else { continue }
            if case .response(let id, let result) = message {
                // Straight to the waiting call, not behind the refresh that
                // is awaiting it.
                HostClient.shared.resolve(id: id, result: result)
            } else if case .runOutput = message {
                HostClient.shared.deliver(run: message)
            } else if case .runExit = message {
                HostClient.shared.deliver(run: message)
            } else {
                mailbox.push(message)
            }
        }
    }

    static func printManifest(_ manifest: Manifest) {
        guard let data = try? LineCodec.encode(manifest) else { return }
        FileHandle.standardOutput.write(data)
    }

    static func printPreviews(_ previews: [PreviewSpec]) {
        guard let data = try? LineCodec.encode(previews) else { return }
        FileHandle.standardOutput.write(data)
    }
}
