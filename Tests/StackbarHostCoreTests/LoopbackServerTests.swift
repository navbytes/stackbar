import XCTest
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
@testable import StackbarHostCore

final class LoopbackServerTests: XCTestCase {
    private func raw(_ request: String, to port: UInt16) -> String {
        #if canImport(Glibc)
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else { return "" }
        _ = Array(request.utf8).withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
        var out = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count <= 0 { break }
            out.append(contentsOf: buffer[0..<count])
        }
        return String(decoding: out, as: UTF8.self)
    }

    func testANegativeContentLengthIsAnEmptyBodyNotACrash() {
        let server = try! LoopbackServer { request in .text("body=\(request.body.count)") }
        defer { server.stop() }
        let reply = raw("POST /x HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: -5\r\n\r\n", to: server.port)
        XCTAssertTrue(reply.hasSuffix("body=0"), reply)
    }

    func testListeningSocketsAreNotInheritedByHelpers() throws {
        let server = try LoopbackServer { _ in .text("ok") }
        defer { server.stop() }
        let flags = fcntl(try XCTUnwrap(Mirror(reflecting: server).children.first { $0.label == "socketFD" }?.value as? Int32), F_GETFD)
        XCTAssertNotEqual(flags & FD_CLOEXEC, 0)
    }

    func testStopEndsTheAcceptLoopQuickly() throws {
        let server = try LoopbackServer { _ in .text("ok") }
        let port = server.port
        server.stop()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(raw("GET / HTTP/1.1\r\n\r\n", to: port), "")
    }
}
