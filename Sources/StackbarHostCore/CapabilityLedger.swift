import Foundation
import StackbarProtocol

/// What the user approved each plugin to do: enforced trust.
///
/// When a plugin is new, or an update asks for capabilities it didn't have,
/// the host shows the difference and runs the plugin with only what was
/// approved until the user agrees. Host calls outside the approved set fail,
/// so an update can't quietly start reading a new secret or a new domain.
/// Removing capabilities never needs approval.
public final class CapabilityLedger: @unchecked Sendable {
    public struct Approval: Codable, Equatable, Sendable {
        public var version: String
        public var capabilities: [Capability]
        public var approvedAt: Date
        /// What each `.run` command name resolved to when the user approved
        /// it. The host runs these paths and nothing else; a name that later
        /// resolves elsewhere needs approving again.
        public var commandPaths: [String: String]?
    }

    public enum Review: Equatable, Sendable {
        /// Nothing new to approve; run with `granted`.
        case approved(granted: [Capability])
        /// Needs the user's yes. Until then, run with `granted` (what was
        /// approved before, minus anything the plugin no longer asks for).
        case needsApproval(added: [Capability], removed: [Capability], granted: [Capability], isNew: Bool)

        public var granted: [Capability] {
            switch self {
            case .approved(let granted), .needsApproval(_, _, let granted, _): return granted
            }
        }
    }

    public let file: URL
    public let resolver: CommandResolver
    private let lock = NSLock()
    private var approvals: [String: Approval]

    public init(file: URL, resolver: CommandResolver = .standard) {
        self.file = file
        self.resolver = resolver
        self.approvals = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder.ledger.decode([String: Approval].self, from: $0) } ?? [:]
    }

    public func approval(for pluginID: String) -> Approval? {
        lock.withLock { approvals[pluginID] }
    }

    public func review(_ manifest: Manifest) -> Review {
        let requested = manifest.capabilities
        guard let previous = approval(for: manifest.id) else {
            return requested.isEmpty ? .approved(granted: []) : .needsApproval(added: requested, removed: [], granted: [], isNew: true)
        }
        var added = requested.filter { !previous.capabilities.contains($0) }
        let removed = previous.capabilities.filter { !requested.contains($0) }
        var granted = requested.filter(previous.capabilities.contains)
        // A command that now resolves to a different program is new to the
        // user: its `.run` capability goes back on the sheet.
        let moved = Set(movedCommands(manifest))
        if !moved.isEmpty {
            let stale = granted.filter { capability in
                if case .run(let commands) = capability { return commands.contains(where: moved.contains) }
                return false
            }
            granted.removeAll(where: stale.contains)
            added += stale
        }
        return added.isEmpty ? .approved(granted: granted) : .needsApproval(added: added, removed: removed, granted: granted, isNew: false)
    }

    /// Declared commands that resolve now to a program other than the one
    /// approved, or that were approved before paths were recorded.
    public func movedCommands(_ manifest: Manifest) -> [String] {
        guard let previous = approval(for: manifest.id) else { return [] }
        let approved = previous.capabilities.flatMap { capability -> [String] in
            if case .run(let commands) = capability { return commands }
            return []
        }
        return manifest.runCommands.filter { name in
            guard approved.contains(name), let now = resolver.resolve(name) else { return false }
            return previous.commandPaths?[name] != now
        }
    }

    /// The programs the user approved the plugin to run, by declared name.
    public func approvedCommandPaths(for pluginID: String) -> [String: String] {
        approval(for: pluginID)?.commandPaths ?? [:]
    }

    public func approve(_ manifest: Manifest, at date: Date = Date()) throws {
        let paths = resolver.resolve(all: manifest.runCommands)
        try lock.withLock {
            approvals[manifest.id] = Approval(version: manifest.version, capabilities: manifest.capabilities, approvedAt: date, commandPaths: paths.isEmpty ? nil : paths)
            try save()
        }
    }

    public func revoke(_ pluginID: String) throws {
        try lock.withLock {
            approvals[pluginID] = nil
            try save()
        }
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.ledger.encode(approvals).write(to: file, options: .atomic)
    }
}

extension JSONEncoder {
    static var ledger: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var ledger: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
