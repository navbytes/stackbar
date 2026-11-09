import Foundation
import StackbarProtocol
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// A line-oriented Unix domain socket: the app serves its agent gateway on
/// one, and `stackbarctl agent` bridges an agent's stdio to it.
///
/// The socket file is created with mode 0600 inside the user's own data
/// directory, so only the user's processes can connect.
public final class UnixSocketServer: @unchecked Sendable {
    public typealias Handler = @Sendable (Data) async -> Data?

    public let path: String
    private let fd: Int32
    private let handler: Handler
    private let lock = NSLock()
    private var stopped = false

    public init(path: String, handler: @escaping Handler) throws {
        unlink(path)
        let fd = UnixSocket.makeSocket()
        guard fd >= 0 else { throw UnixSocket.SocketError.socket(errno) }
        var address = try UnixSocket.address(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else {
            let error = errno
            close(fd)
            throw UnixSocket.SocketError.bind(error)
        }
        chmod(path, 0o600)
        guard listen(fd, 16) == 0 else {
            let error = errno
            close(fd)
            throw UnixSocket.SocketError.bind(error)
        }
        self.path = path
        self.fd = fd
        self.handler = handler
        Thread { [self] in acceptLoop() }.start()
    }

    deinit { stop() }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }
        stopped = true
        shutdown(fd, Int32(SHUT_RDWR))
        close(fd)
        unlink(path)
    }

    private var isStopped: Bool { lock.withLock { stopped } }

    private func acceptLoop() {
        while !isStopped {
            guard let client = UnixSocket.acceptClient(on: fd, isStopped: { isStopped }) else { continue }
            let handler = handler
            Thread {
                UnixSocket.serve(client, handler: handler)
                close(client)
            }.start()
        }
    }
}

public enum UnixSocket {
    static func makeSocket() -> Int32 {
        #if canImport(Glibc)
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        #endif
        setCloseOnExec(fd)
        return fd
    }

    /// Keeps `fd` out of helpers spawned later: posix_spawn hands every
    /// inheritable descriptor to the child.
    static func setCloseOnExec(_ fd: Int32) {
        guard fd >= 0 else { return }
        _ = fcntl(fd, F_SETFD, fcntl(fd, F_GETFD) | FD_CLOEXEC)
    }

    /// One turn of an accept loop. Waits at most a quarter second for a
    /// connection, so a loop whose socket was stopped notices even where
    /// closing a listening socket does not wake `accept` (macOS), and backs
    /// off when accept keeps failing (out of descriptors) instead of
    /// spinning. Returns nil when there is no client yet.
    static func acceptClient(on fd: Int32, isStopped: () -> Bool) -> Int32? {
        var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ready = poll(&poller, 1, 250)
        if isStopped() { return nil }
        if ready < 0 {
            if errno != EINTR { usleep(50_000) }
            return nil
        }
        if ready == 0 { return nil }
        if poller.revents & Int16(POLLIN) == 0 {
            // Error or hang-up on a socket that was not stopped through us.
            usleep(50_000)
            return nil
        }
        let client = accept(fd, nil, nil)
        if client < 0 {
            if errno != EINTR && errno != ECONNABORTED && errno != EAGAIN { usleep(50_000) }
            return nil
        }
        setCloseOnExec(client)
        return client
    }

    static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw SocketError.pathTooLong(path) }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }

    /// Reads lines from `client`, answers each through `handler`, until EOF.
    static func serve(_ client: Int32, handler: @escaping UnixSocketServer.Handler) {
        var buffer = LineBufferBox()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = recv(client, &chunk, chunk.count, 0)
            guard count > 0 else { return }
            for line in buffer.append(Data(chunk[0..<count])) {
                let reply = BlockingTask.run { await handler(line) }
                if let reply { writeAll(reply, to: client) }
            }
        }
    }

    static func writeAll(_ data: Data, to fd: Int32) {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let sent = send(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset, 0)
                if sent <= 0 { return }
                offset += sent
            }
        }
    }

    /// Sends one line to the socket at `path` and returns the answer: the
    /// first line that comes back, or everything until the server closes.
    public static func request(_ line: Data, to path: String) throws -> Data {
        let fd = makeSocket()
        guard fd >= 0 else { throw SocketError.socket(errno) }
        defer { close(fd) }
        var address = try address(path)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw SocketError.connect(errno) }
        writeAll(line + Data("\n".utf8), to: fd)
        // Nothing more to send: the server answers, sees the end and closes.
        shutdown(fd, Int32(SHUT_WR))
        var reply = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = recv(fd, &chunk, chunk.count, 0)
            guard count > 0 else { break }
            reply.append(contentsOf: chunk[0..<count])
            if let newline = reply.firstIndex(of: UInt8(ascii: "\n")) { return reply[..<newline] }
        }
        return reply
    }

    /// Connects stdin/stdout to the socket at `path` until either side closes.
    /// This is all `stackbarctl agent` does when the app is running.
    public static func bridgeStdio(to path: String) throws {
        let fd = makeSocket()
        guard fd >= 0 else { throw SocketError.socket(errno) }
        var address = try address(path)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else {
            let error = errno
            close(fd)
            throw SocketError.connect(error)
        }
        let done = DispatchSemaphore(value: 0)
        Thread {
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = recv(fd, &chunk, chunk.count, 0)
                guard count > 0 else { break }
                FileHandle.standardOutput.write(Data(chunk[0..<count]))
            }
            done.signal()
        }.start()
        Thread {
            while withAutoreleasePool({ () -> Bool in
                let data = FileHandle.standardInput.availableData
                if data.isEmpty { return false }
                writeAll(data, to: fd)
                return true
            }) {}
            shutdown(fd, Int32(SHUT_WR))
        }.start()
        done.wait()
        close(fd)
    }

    public enum SocketError: Error, CustomStringConvertible {
        case socket(Int32)
        case bind(Int32)
        case connect(Int32)
        case pathTooLong(String)

        public var description: String {
            switch self {
            case .socket(let code): return "could not open a socket (errno \(code))"
            case .bind(let code): return "could not listen on the agent socket (errno \(code))"
            case .connect(let code): return "could not connect to Stackbar's agent socket (errno \(code)); is Stackbar running?"
            case .pathTooLong(let path): return "socket path is too long: \(path)"
            }
        }
    }
}

/// A `LineBuffer` usable from a plain thread.
struct LineBufferBox {
    private var buffer = LineBuffer()
    mutating func append(_ data: Data) -> [Data] { buffer.append(data) }
}

/// Runs async work from a plain thread and waits for it. Only for the socket
/// threads, which exist to block.
enum BlockingTask {
    static func run<T: Sendable>(_ body: @escaping @Sendable () async -> T) -> T {
        let box = ResultBox<T>()
        let done = DispatchSemaphore(value: 0)
        Task {
            box.value = await body()
            done.signal()
        }
        done.wait()
        return box.value!
    }

    final class ResultBox<T>: @unchecked Sendable {
        var value: T?
    }
}
