import Foundation
@testable import FluidHostCore

/// Collects log lines from supervisor updates, from any thread.
final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ update: PluginSupervisor.Update) {
        if case .log(_, let line) = update { lock.withLock { lines.append(line) } }
    }
    var all: [String] { lock.withLock { lines } }
}

func waitUntil(_ timeout: Double = 15, _ condition: () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return false
}
