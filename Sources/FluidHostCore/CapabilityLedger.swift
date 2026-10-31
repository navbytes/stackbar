import Foundation
import FluidProtocol

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
    private let lock = NSLock()
    private var approvals: [String: Approval]

    public init(file: URL) {
        self.file = file
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
        let added = requested.filter { !previous.capabilities.contains($0) }
        let removed = previous.capabilities.filter { !requested.contains($0) }
        let granted = requested.filter(previous.capabilities.contains)
        return added.isEmpty ? .approved(granted: granted) : .needsApproval(added: added, removed: removed, granted: granted, isNew: false)
    }

    public func approve(_ manifest: Manifest, at date: Date = Date()) throws {
        try lock.withLock {
            approvals[manifest.id] = Approval(version: manifest.version, capabilities: manifest.capabilities, approvedAt: date)
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
