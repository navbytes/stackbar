import Foundation

/// Routes topic messages between plugins: plugin pub/sub.
///
/// A plugin listens with a `.topic(name:)` trigger and publishes with
/// `Fluid.publish`. The bus never delivers a message back to its sender, caps
/// payloads, and keeps no history: a plugin that isn't running misses what was
/// published meanwhile, the same as a notification you weren't there for.
public actor PluginBus {
    public typealias Deliver = @Sendable (_ topic: String, _ payload: String, _ from: String) -> Void
    public static let maxPayloadBytes = 64 * 1024

    private var subscribers: [String: [String: Deliver]] = [:]
    public private(set) var delivered = 0

    public init() {}

    public func subscribe(_ pluginID: String, to topics: [String], deliver: @escaping Deliver) {
        for topic in topics { subscribers[topic, default: [:]][pluginID] = deliver }
    }

    public func unsubscribe(_ pluginID: String) {
        for topic in subscribers.keys { subscribers[topic]?[pluginID] = nil }
    }

    /// Returns how many plugins received the message.
    @discardableResult
    public func publish(_ topic: String, payload: String, from pluginID: String) throws -> Int {
        guard !topic.isEmpty, topic.count <= 200 else { throw BusError.badTopic }
        guard payload.utf8.count <= Self.maxPayloadBytes else { throw BusError.tooLarge(payload.utf8.count) }
        let targets = (subscribers[topic] ?? [:]).filter { $0.key != pluginID }
        for (_, deliver) in targets { deliver(topic, payload, pluginID) }
        delivered += targets.count
        return targets.count
    }

    public func listeners(of topic: String) -> [String] {
        (subscribers[topic] ?? [:]).keys.sorted()
    }

    public enum BusError: Error, CustomStringConvertible {
        case badTopic
        case tooLarge(Int)

        public var description: String {
            switch self {
            case .badTopic: return "topic names are 1 to 200 characters"
            case .tooLarge(let bytes): return "payload is \(bytes) bytes; the limit is \(PluginBus.maxPayloadBytes)"
            }
        }
    }
}
