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

    init() {
        let protocolFD = dup(STDOUT_FILENO)
        dup2(STDERR_FILENO, STDOUT_FILENO)
        output = FileHandle(fileDescriptor: protocolFD, closeOnDealloc: true)
    }

    var send: PluginRuntime.Send {
        { [self] message in
            guard let data = try? LineCodec.encode(message) else { return }
            // Flush C stdio (where `print` buffers, now pointed at stderr) so a
            // stray print reaches the log alongside the message it preceded.
            fflush(nil)
            lock.lock()
            defer { lock.unlock() }
            output.write(data)
        }
    }

    /// Host messages, read on a dedicated thread so a blocking read never
    /// holds the main actor. Undecodable lines are skipped; EOF ends the stream.
    func incoming() -> AsyncStream<HostMessage> {
        AsyncStream { continuation in
            // Raw reads, not `readLine`: a thread parked in C stdio's stdin
            // would hold a lock that the `fflush(nil)` in `send` also takes.
            let reader = Thread {
                let input = FileHandle.standardInput
                var buffer = LineBuffer()
                while true {
                    // Each read gets its own autorelease pool: on macOS
                    // `availableData` and the decoding behind it hand back
                    // autoreleased objects, and this thread's outer pool
                    // would only drain when the plugin exits, so memory
                    // grew with every message.
                    let more = withAutoreleasePool {
                        let chunk = input.availableData
                        if chunk.isEmpty { return false }
                        Self.dispatch(buffer.append(chunk), to: continuation)
                        return true
                    }
                    if !more { break }
                }
                // The host is gone (it quit or crashed). Fail waiting host
                // calls so the runtime loop can finish, and don't outlive the
                // host even if plugin code is stuck.
                HostClient.shared.failAll("the host went away")
                continuation.finish()
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) { exit(0) }
            }
            reader.start()
        }
    }

    private static func dispatch(_ lines: [Data], to continuation: AsyncStream<HostMessage>.Continuation) {
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
                continuation.yield(message)
            }
        }
    }

    static func printManifest(_ manifest: Manifest) {
        guard let data = try? LineCodec.encode(manifest) else { return }
        FileHandle.standardOutput.write(data)
    }
}
