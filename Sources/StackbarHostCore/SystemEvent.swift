import Foundation
import StackbarProtocol

/// A change on the Mac that plugins can ask to hear about (protocol 26).
public enum SystemEvent: String, CaseIterable, Sendable {
    case locked, unlocked, sleep, frontApp, power, audio, network, volumes

    /// The trigger a plugin declares to hear it.
    public var trigger: Trigger {
        switch self {
        case .locked, .unlocked: return .lock
        case .sleep: return .sleep
        case .frontApp: return .frontApp
        case .power: return .power
        case .audio: return .audio
        case .network: return .network
        case .volumes: return .volumes
        }
    }

    /// What `Stackbar.refreshReason` says.
    public var reason: TriggerReason {
        switch self {
        case .locked: return .locked
        case .unlocked: return .unlocked
        case .sleep: return .sleep
        case .frontApp: return .frontApp
        case .power: return .power
        case .audio: return .audio
        case .network: return .network
        case .volumes: return .volumes
        }
    }

    /// How long to wait for the burst to settle before plugins hear it:
    /// network and audio changes come several at a time.
    public var settle: Duration {
        switch self {
        case .network, .audio, .volumes: return .milliseconds(1000)
        case .frontApp: return .milliseconds(300)
        case .locked, .unlocked, .sleep, .power: return .zero
        }
    }
}
