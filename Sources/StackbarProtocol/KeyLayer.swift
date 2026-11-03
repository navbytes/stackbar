import Foundation

// Values for the app calls and the key layer (protocol 14): which apps are
// running, and a held key plus a letter that switches between them. The host
// owns the keyboard listener and decides on each press itself, so plugins
// stay sandboxed and a switch never waits on a plugin. These types cross the
// wire as JSON inside `HostResult.value`.

/// A regular (Dock) app that is running.
public struct RunningApp: Codable, Equatable, Hashable, Sendable {
    /// The bundle id, like `com.apple.Safari`.
    public var id: String
    public var name: String
    /// Where the app is, for its icon (`Row(appIcon:)`).
    public var path: String?
    /// The app in front.
    public var isActive: Bool
    public var isHidden: Bool

    public init(id: String, name: String, path: String? = nil, isActive: Bool = false, isHidden: Bool = false) {
        self.id = id
        self.name = name
        self.path = path
        self.isActive = isActive
        self.isHidden = isHidden
    }
}

/// The key a key layer is held with. Only right-hand modifiers, so the left
/// ones keep every shortcut they have.
public enum KeyLayerTrigger: String, Codable, CaseIterable, Sendable {
    case rightCommand, rightOption, rightControl, rightShift

    /// How a person reads it: "Right ⌘".
    public var title: String {
        switch self {
        case .rightCommand: return "Right ⌘"
        case .rightOption: return "Right ⌥"
        case .rightControl: return "Right ⌃"
        case .rightShift: return "Right ⇧"
        }
    }
}

/// What pressing a letter again does when its only running app is already
/// in front.
public enum SecondPress: String, Codable, CaseIterable, Sendable {
    /// Hides the app, as ⌘H would.
    case hide
    /// Brings the app's backmost window to the front.
    case cycleWindows
    /// Nothing.
    case stay
}

/// One key of a layer and the apps it switches to.
public struct KeyBinding: Codable, Equatable, Hashable, Sendable {
    /// One lowercase letter or digit.
    public var key: String
    /// Bundle ids, in the order pressing the key again cycles through them.
    public var apps: [String]
    /// Opens the first app when none of them is running.
    public var launch: Bool

    public init(key: String, apps: [String], launch: Bool = false) {
        self.key = key
        self.apps = apps
        self.launch = launch
    }

    /// One lowercase letter a–z or digit 0–9.
    public static func isValidKey(_ key: String) -> Bool {
        key.count == 1 && key.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
    }
}

/// A held key and the letters that switch apps while it is held.
public struct KeyLayer: Codable, Equatable, Sendable {
    public var trigger: KeyLayerTrigger
    public var bindings: [KeyBinding]
    public var secondPress: SecondPress
    /// A command of the plugin's that the host runs when the trigger, Right ⌥
    /// and a key are held together, with the arguments `key` and `app` (the
    /// frontmost app's bundle id). `nil`: that chord does nothing.
    public var assignCommand: String?
    /// Shows the letter map while the trigger is held on its own.
    public var overlay: Bool

    public static let maxBindings = 36
    public static let maxAppsPerKey = 20

    public init(trigger: KeyLayerTrigger = .rightCommand, bindings: [KeyBinding], secondPress: SecondPress = .hide, assignCommand: String? = nil, overlay: Bool = true) {
        self.trigger = trigger
        self.bindings = bindings
        self.secondPress = secondPress
        self.assignCommand = assignCommand
        self.overlay = overlay
    }

    /// The binding for `key`, if any.
    public func binding(for key: String) -> KeyBinding? { bindings.first { $0.key == key } }

    /// Problems that make the layer unusable, in words. Empty means valid.
    public var problems: [String] {
        var result: [String] = []
        if bindings.count > Self.maxBindings { result.append("at most \(Self.maxBindings) keys") }
        var seen: Set<String> = []
        for binding in bindings {
            if !KeyBinding.isValidKey(binding.key) { result.append("key \"\(binding.key)\" must be one lowercase letter or digit") }
            if !seen.insert(binding.key).inserted { result.append("key \"\(binding.key)\" is bound twice") }
            if binding.apps.isEmpty { result.append("key \"\(binding.key)\" has no apps") }
            if binding.apps.count > Self.maxAppsPerKey { result.append("key \"\(binding.key)\" has more than \(Self.maxAppsPerKey) apps") }
        }
        return result
    }
}

/// Whether a plugin's key layer is working, and why not.
public struct KeyLayerStatus: Codable, Equatable, Sendable {
    /// Presses reach the layer.
    public var listening: Bool
    /// Stackbar needs Accessibility access before it can listen.
    public var needsAccessibility: Bool
    /// The app holding Secure Input, which blocks every key listener while
    /// it is on (password fields turn it on; some apps leave it on).
    public var secureInputApp: String?
    /// The plugin already holding this trigger; this layer isn't listened to.
    public var conflict: String?

    public init(listening: Bool = false, needsAccessibility: Bool = false, secureInputApp: String? = nil, conflict: String? = nil) {
        self.listening = listening
        self.needsAccessibility = needsAccessibility
        self.secureInputApp = secureInputApp
        self.conflict = conflict
    }

    /// No layer is registered.
    public static let off = KeyLayerStatus()
}
