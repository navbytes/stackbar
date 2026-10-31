import Foundation
import StackbarProtocol

/// What each plugin actually reached through the host, compared with what it
/// declared: the "observed network use" half of enforced trust.
///
/// Every host-mediated request is recorded, allowed or refused. A refused
/// host is one the plugin tried to reach without declaring it, which is worth
/// showing the user even though the request never left the Mac.
public final class NetworkAudit: @unchecked Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var host: String
        public var allowed: Int
        public var refused: Int
        public var lastUsed: Date
    }

    private let lock = NSLock()
    private var entries: [String: [String: Entry]] = [:]

    public init() {}

    public func record(pluginID: String, host: String, allowed: Bool, at date: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        var entry = entries[pluginID]?[host] ?? Entry(host: host, allowed: 0, refused: 0, lastUsed: date)
        if allowed { entry.allowed += 1 } else { entry.refused += 1 }
        entry.lastUsed = date
        entries[pluginID, default: [:]][host] = entry
    }

    public func entries(for pluginID: String) -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return (entries[pluginID] ?? [:]).values.sorted { $0.host < $1.host }
    }

    /// Declared hosts the plugin never used (candidates to drop), and hosts it
    /// tried without declaring them.
    public func report(for manifest: Manifest) -> Report {
        let used = entries(for: manifest.id)
        let declared = manifest.networkHosts
        let unused = declared.filter { pattern in !used.contains { $0.allowed > 0 && URLParts.host($0.host, matches: [pattern]) } }
        return Report(used: used, declaredButUnused: unused, undeclared: used.filter { $0.refused > 0 }.map(\.host))
    }

    public struct Report: Equatable, Sendable {
        public var used: [Entry]
        public var declaredButUnused: [String]
        public var undeclared: [String]

        public var lines: [String] {
            var lines = used.map { "\($0.host): \($0.allowed) allowed" + ($0.refused > 0 ? ", \($0.refused) refused" : "") }
            if !declaredButUnused.isEmpty { lines.append("declared but not used: " + declaredButUnused.joined(separator: ", ")) }
            if !undeclared.isEmpty { lines.append("tried without declaring: " + undeclared.joined(separator: ", ")) }
            return lines.isEmpty ? ["no network use yet"] : lines
        }
    }
}
