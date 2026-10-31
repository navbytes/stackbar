import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// A tiny HTTP/1.1 server on 127.0.0.1, one connection at a time.
///
/// It exists for the OAuth loopback redirect (RFC 8252), where the browser
/// delivers the authorization code to `http://127.0.0.1:<port>/callback`, and
/// for tests that need a fake authorization server. It is not a general web
/// server: requests are capped at 1 MB and handled serially.
public final class LoopbackServer: @unchecked Sendable {
    public struct Request: Sendable {
        public var method: String
        public var path: String
        public var query: [String: String]
        public var headers: [String: String]
        public var body: Data

        /// The body parsed as `application/x-www-form-urlencoded`.
        public var form: [String: String] { LoopbackServer.parseQuery(String(decoding: body, as: UTF8.self)) }
    }

    public struct Response: Sendable {
        public var status: Int
        public var contentType: String
        public var body: Data

        public init(status: Int = 200, contentType: String = "text/plain; charset=utf-8", body: Data) {
            self.status = status
            self.contentType = contentType
            self.body = body
        }

        public static func text(_ text: String, status: Int = 200) -> Response { Response(status: status, body: Data(text.utf8)) }
        public static func html(_ html: String, status: Int = 200) -> Response { Response(status: status, contentType: "text/html; charset=utf-8", body: Data(html.utf8)) }
        public static func json(_ json: String, status: Int = 200) -> Response { Response(status: status, contentType: "application/json", body: Data(json.utf8)) }
    }

    public let port: UInt16
    private let socketFD: Int32
    private let handler: @Sendable (Request) -> Response
    private let lock = NSLock()
    private var stopped = false

    /// Binds to 127.0.0.1 on `port` (0 picks a free one) and starts serving.
    public init(port: UInt16 = 0, handler: @escaping @Sendable (Request) -> Response) throws {
        #if canImport(Glibc)
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard fd >= 0 else { throw LoopbackError.socket(errno) }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            let error = errno
            close(fd)
            throw LoopbackError.bind(error)
        }
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        self.port = UInt16(bigEndian: actual.sin_port)
        self.socketFD = fd
        self.handler = handler
        let thread = Thread { [self] in acceptLoop() }
        thread.start()
    }

    deinit { stop() }

    public var baseURL: String { "http://127.0.0.1:\(port)" }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }
        stopped = true
        shutdown(socketFD, Int32(SHUT_RDWR))
        close(socketFD)
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    private func acceptLoop() {
        while !isStopped {
            let client = accept(socketFD, nil, nil)
            if client < 0 {
                if isStopped { return }
                continue
            }
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            serve(client)
            close(client)
        }
    }

    private func serve(_ client: Int32) {
        guard let request = Self.read(client) else {
            Self.write(.text("bad request", status: 400), to: client)
            return
        }
        Self.write(handler(request), to: client)
    }

    static func read(_ client: Int32) -> Request? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        let separator = Data("\r\n\r\n".utf8)
        var headerEnd: Range<Data.Index>?
        while headerEnd == nil {
            let count = recv(client, &buffer, buffer.count, 0)
            guard count > 0 else { return nil }
            data.append(contentsOf: buffer[0..<count])
            headerEnd = data.range(of: separator)
            if data.count > 64 * 1024 && headerEnd == nil { return nil }
        }
        guard let headerEnd else { return nil }
        let head = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        var body = Data(data[headerEnd.upperBound...])
        let expected = min(Int(headers["content-length"] ?? "") ?? 0, 1024 * 1024)
        while body.count < expected {
            let count = recv(client, &buffer, buffer.count, 0)
            guard count > 0 else { break }
            body.append(contentsOf: buffer[0..<count])
        }
        let target = String(requestLine[1])
        let parts = target.split(separator: "?", maxSplits: 1)
        return Request(
            method: String(requestLine[0]),
            path: String(parts.first ?? "/"),
            query: parts.count > 1 ? parseQuery(String(parts[1])) : [:],
            headers: headers,
            body: body.prefix(expected)
        )
    }

    static func write(_ response: Response, to client: Int32) {
        let reason = [200: "OK", 302: "Found", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 500: "Internal Server Error"][response.status] ?? "Status"
        var data = Data("HTTP/1.1 \(response.status) \(reason)\r\nContent-Type: \(response.contentType)\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n".utf8)
        data.append(response.body)
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let sent = send(client, raw.baseAddress!.advanced(by: offset), raw.count - offset, 0)
                if sent <= 0 { return }
                offset += sent
            }
        }
    }

    public static func parseQuery(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            let decode = { (text: Substring) in text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(text) }
            if let key = parts.first { result[decode(key)] = parts.count > 1 ? decode(parts[1]) : "" }
        }
        return result
    }

    public enum LoopbackError: Error, CustomStringConvertible {
        case socket(Int32)
        case bind(Int32)

        public var description: String {
            switch self {
            case .socket(let code): return "could not open a socket (errno \(code))"
            case .bind(let code): return "could not listen on 127.0.0.1 (errno \(code))"
            }
        }
    }
}

extension String {
    /// Percent-encodes for a query value or form field.
    var formEncoded: String {
        // ASCII only: `CharacterSet.alphanumerics` also holds letters like é,
        // which must be percent-encoded in a URL.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
