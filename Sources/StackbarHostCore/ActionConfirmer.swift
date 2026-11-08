import Foundation
import StackbarProtocol

/// The host's "press again to confirm" for actions that carry `confirm`
/// (protocol 25), so no plugin keeps its own copy of the state machine.
///
/// ```
/// idle ──press──▶ armed(at, text) ──press within `window`──▶ send (idle)
///                     ├── `window` passes ─────────────────▶ idle (redraw)
///                     ├── a new tree drops the action ──────▶ idle
///                     ├── a new tree changes its text ──────▶ idle
///                     └── another action, Esc, hidden ──────▶ idle
/// ```
///
/// One arm at a time per owner: the app keeps one per plugin (panel, window,
/// settings and the palette's rows from the panel), and each command view
/// keeps its own. It is keyed by surface and action id, never by position, and
/// it compares the text again on the second press, so "Remove 3" armed and
/// "Remove 4" shown is a new first press rather than a confirmation of
/// something the user didn't read.
///
/// It holds no clock and no timer: callers pass `now` and call `expire(now:)`
/// when `deadline` passes, so it is tested without waiting.
public struct ActionConfirmer: Equatable, Sendable {
    /// How long an arm lasts.
    public static let window: TimeInterval = 10

    public struct Arm: Equatable, Sendable {
        public var surface: Surface?
        public var action: ActionID
        /// The action's `confirm`, as it was when armed.
        public var text: String
        public var at: Date

        public var deadline: Date { at.addingTimeInterval(ActionConfirmer.window) }
        /// What the HUD and VoiceOver say.
        public var prompt: String { ActionConfirmer.prompt(text) }
    }

    public enum Outcome: Equatable, Sendable {
        /// Send the action to the plugin now.
        case send
        /// Held: show `prompt`, redraw, and send nothing.
        case armed(Arm)
    }

    public private(set) var arm: Arm?

    public init() {}

    /// "Press again within 10 s to stop web (pid 412)".
    public static func prompt(_ text: String) -> String {
        "Press again within \(Int(window)) s to \(text)"
    }

    /// What the armed control says in place of its title.
    public static func armedTitle(_ text: String) -> String {
        "Press again to \(text)"
    }

    /// A press of `action` on `surface`, whose current tree is `root`. An
    /// action without `confirm` is sent, and disarms whatever was armed: the
    /// user moved on.
    public mutating func press(_ action: ActionID, surface: Surface?, in root: ViewNode?, now: Date = Date()) -> Outcome {
        guard let text = root?.confirmations[action] else {
            arm = nil
            return .send
        }
        if let arm, arm.action == action, arm.surface == surface, arm.text == text, now < arm.deadline {
            self.arm = nil
            return .send
        }
        let next = Arm(surface: surface, action: action, text: text, at: now)
        arm = next
        return .armed(next)
    }

    /// A new tree arrived for `surface`. Returns whether the arm was dropped
    /// because the action is gone or now says something else.
    @discardableResult
    public mutating func rendered(_ root: ViewNode?, surface: Surface?) -> Bool {
        guard let arm, arm.surface == surface else { return false }
        guard root?.confirmations[arm.action] != arm.text else { return false }
        self.arm = nil
        return true
    }

    /// Drops the arm once its window has passed. Returns whether it did, so
    /// the caller redraws.
    @discardableResult
    public mutating func expire(now: Date = Date()) -> Bool {
        guard let arm, now >= arm.deadline else { return false }
        self.arm = nil
        return true
    }

    /// Esc, the surface closing, the plugin stopping. Returns whether
    /// anything was armed.
    @discardableResult
    public mutating func cancel(surface: Surface? = nil) -> Bool {
        guard let arm, surface == nil || arm.surface == surface else { return false }
        self.arm = nil
        return true
    }

    /// `root` as it should be drawn on `surface`: the armed control says
    /// "Press again to …" in the critical color, so every renderer shows the
    /// state without knowing about it. Unarmed trees come back unchanged.
    public func decorate(_ root: ViewNode, surface: Surface?) -> ViewNode {
        guard let arm, arm.surface == surface else { return root }
        return Self.decorate(root, arm: arm)
    }

    static func decorate(_ node: ViewNode, arm: Arm) -> ViewNode {
        let title = armedTitle(arm.text)
        switch node {
        case .button(_, let symbol, _, let action, let confirm) where action == arm.action:
            return .button(title: title, symbol: symbol ?? "exclamationmark.circle", role: .critical, action: action, confirm: confirm)
        case .tappable(let content, let action, let confirm) where action == arm.action:
            var style = Style()
            style.accessibilityLabel = title
            let marked: ViewNode = .stack(axis: .horizontal, spacing: 6, children: [
                content,
                .label(title, symbol: "exclamationmark.circle", role: .critical),
            ])
            return .tappable(.styled(marked, style: style), action: action, confirm: confirm)
        case .row(var row) where row.actions.contains(where: { $0.id == arm.action }):
            row.subtitle = title
            row.actions = row.actions.map { ref in
                guard ref.id == arm.action else { return ref }
                var ref = ref
                ref.title = title
                ref.role = .critical
                return ref
            }
            return .row(row)
        default:
            return node.mapChildren { decorate($0, arm: arm) }
        }
    }
}
