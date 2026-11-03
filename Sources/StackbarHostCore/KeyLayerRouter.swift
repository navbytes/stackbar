import Foundation
import StackbarProtocol

/// What one key press does under the registered key layers. Pure, so the
/// rules rcmd users expect are tested on Linux; the Mac tap and the simulated
/// system both apply its answer.
public enum KeyLayerRouter {
    public enum Decision: Equatable, Sendable {
        /// Not ours: the app in front gets the key as usual.
        case passThrough
        /// Ours, with nothing to do; the app in front doesn't get it either.
        case swallow
        case activate(String)
        case launch(String)
        case hide(String)
        case cycleWindows(String)
        /// Run the plugin's assign command for this key and frontmost app.
        case assign(pluginID: String, command: String, key: String, app: String)
    }

    /// The modifier that turns a press into an assignment: Right ⌥, or
    /// Right ⌘ for a layer held with Right ⌥.
    public static func assignModifier(for trigger: KeyLayerTrigger) -> KeyLayerTrigger {
        trigger == .rightOption ? .rightCommand : .rightOption
    }

    /// - Parameters:
    ///   - key: the character the key types without modifiers, lowercased.
    ///   - held: the right-hand modifiers held down.
    ///   - layers: the listening layers (`KeyLayerRegistry.listening`).
    ///   - running: the regular apps that are running, `isActive` marking
    ///     the one in front.
    public static func route(key: String, held: Set<KeyLayerTrigger>, layers: [KeyLayerRegistry.Registration], running: [RunningApp]) -> Decision {
        guard let registration = layers.first(where: { held.contains($0.layer.trigger) }) else { return .passThrough }
        let layer = registration.layer
        let key = key.lowercased()

        if held.contains(assignModifier(for: layer.trigger)) {
            guard KeyBinding.isValidKey(key) else { return .passThrough }
            guard let command = layer.assignCommand, let front = running.first(where: \.isActive) else { return .swallow }
            return .assign(pluginID: registration.pluginID, command: command, key: key, app: front.id)
        }

        guard let binding = layer.binding(for: key) else { return .passThrough }
        let onKey = binding.apps.compactMap { id in running.first { $0.id == id } }
        guard !onKey.isEmpty else { return binding.launch ? .launch(binding.apps[0]) : .swallow }
        guard let current = onKey.firstIndex(where: \.isActive) else { return .activate(onKey[0].id) }
        if onKey.count > 1 { return .activate(onKey[(current + 1) % onKey.count].id) }
        switch layer.secondPress {
        case .hide: return .hide(onKey[current].id)
        case .cycleWindows: return .cycleWindows(onKey[current].id)
        case .stay: return .swallow
        }
    }
}

/// The key layers plugins have registered, at most one each. Two plugins
/// can't hold the same trigger: the one that registered first listens, and
/// the other waits, reporting the conflict, until the first lets go.
public final class KeyLayerRegistry: @unchecked Sendable {
    public struct Registration: Equatable, Sendable {
        public var pluginID: String
        public var pluginName: String
        public var layer: KeyLayer

        public init(pluginID: String, pluginName: String, layer: KeyLayer) {
            self.pluginID = pluginID
            self.pluginName = pluginName
            self.layer = layer
        }
    }

    private let lock = NSLock()
    private var registrations: [Registration] = []
    /// Called after every change, with the layers now listening.
    public var onChange: (@Sendable ([Registration]) -> Void)?

    public init() {}

    /// Registers or replaces a plugin's layer (keeping its place in line);
    /// `nil` removes it. Throws the layer's problems.
    public func set(_ layer: KeyLayer?, pluginID: String, pluginName: String) throws {
        if let layer, let problem = layer.problems.first { throw SystemServiceError(problem) }
        let listening: [Registration] = lock.withLock {
            if let layer {
                let registration = Registration(pluginID: pluginID, pluginName: pluginName, layer: layer)
                if let index = registrations.firstIndex(where: { $0.pluginID == pluginID }) {
                    registrations[index] = registration
                } else {
                    registrations.append(registration)
                }
            } else {
                registrations.removeAll { $0.pluginID == pluginID }
            }
            return listeningLocked()
        }
        onChange?(listening)
    }

    /// The layers presses go to: for each trigger, the first registered.
    public var listening: [Registration] { lock.withLock { listeningLocked() } }

    public var isEmpty: Bool { lock.withLock { registrations.isEmpty } }

    public func registration(for pluginID: String) -> Registration? {
        lock.withLock { registrations.first { $0.pluginID == pluginID } }
    }

    /// The plugin that holds `pluginID`'s trigger ahead of it, by name.
    public func conflict(for pluginID: String) -> String? {
        lock.withLock {
            guard let index = registrations.firstIndex(where: { $0.pluginID == pluginID }) else { return nil }
            let trigger = registrations[index].layer.trigger
            return registrations[..<index].first { $0.layer.trigger == trigger }?.pluginName
        }
    }

    private func listeningLocked() -> [Registration] {
        var seen: Set<KeyLayerTrigger> = []
        return registrations.filter { seen.insert($0.layer.trigger).inserted }
    }
}
