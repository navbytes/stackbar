@_exported import StackbarProtocol
import Foundation

/// Anything a plugin can put in a view body.
///
/// A view resolves to zero or more `ViewNode`s, registering the closures it
/// carries with the `RenderContext` as it goes. Returning an array lets
/// conditionals and loops flatten into their parent without wrapper nodes.
@MainActor
public protocol StackbarView {
    func resolve(in context: RenderContext) -> [ViewNode]
}

/// What a `@ViewBuilder` body produces.
public typealias ViewContent = [any StackbarView]

extension Array: StackbarView where Element == any StackbarView {
    public func resolve(in context: RenderContext) -> [ViewNode] {
        flatMap { $0.resolve(in: context) }
    }
}

/// Builds view bodies the way SwiftUI does: plain statements, `if`/`else`,
/// `switch`, optionals and `for` loops.
@resultBuilder
public enum ViewBuilder {
    @MainActor public static func buildExpression(_ view: any StackbarView) -> ViewContent { [view] }
    @MainActor public static func buildBlock(_ parts: ViewContent...) -> ViewContent { parts.flatMap { $0 } }
    @MainActor public static func buildOptional(_ part: ViewContent?) -> ViewContent { part ?? [] }
    @MainActor public static func buildEither(first part: ViewContent) -> ViewContent { part }
    @MainActor public static func buildEither(second part: ViewContent) -> ViewContent { part }
    @MainActor public static func buildArray(_ parts: [ViewContent]) -> ViewContent { parts.flatMap { $0 } }
    @MainActor public static func buildLimitedAvailability(_ part: ViewContent) -> ViewContent { part }
}

/// Collects the closures a render registers, so an `event` can find its handler.
///
/// Ids are derived from what the view says about itself — a row's key plus the
/// action's title, a button's title — not from render order, so a click that
/// lands after a re-render still reaches the same closure. Collisions get a
/// `#2`, `#3` suffix rather than silently replacing an earlier handler.
@MainActor
public final class RenderContext {
    public typealias Handler = @MainActor (EventValue?) async throws -> Void

    public private(set) var handlers: [ActionID: Handler] = [:]
    /// Problems found while resolving, logged once by the runtime.
    public private(set) var warnings: [String] = []
    /// The next suffix to try per base, so many same-titled controls don't
    /// probe from `#2` up each time.
    private var nextSuffix: [String: Int] = [:]
    /// Put in front of every id: a command view's handlers live under
    /// `view/<session>/` so they never collide with the panel's.
    public let prefix: String

    public init(prefix: String = "") {
        self.prefix = prefix
    }

    public func register(_ base: String, _ handler: @escaping Handler) -> ActionID {
        let base = prefix + base
        var id = ActionID(base)
        if handlers[id] != nil {
            var suffix = nextSuffix[base] ?? 2
            repeat {
                id = ActionID("\(base)#\(suffix)")
                suffix += 1
            } while handlers[id] != nil
            nextSuffix[base] = suffix
        }
        handlers[id] = handler
        return id
    }

    /// Registers an action that asks for a second press (`Confirm`). The
    /// host does the asking from protocol 25; an older host would send the
    /// first press straight through, so the kit holds it here instead
    /// (`KitConfirmer`). An id that needed a `#2` suffix is logged once:
    /// render order decides which closure it reaches, so a confirmation
    /// could land on the wrong row. Give such rows distinct keys.
    public func register(_ base: String, confirm: String?, _ handler: @escaping Handler) -> ActionID {
        guard let confirm else { return register(base, handler) }
        let key = ActionID(prefix + base)
        let held: Handler = { value in
            guard KitConfirmer.shared.pass(key, text: confirm) else { return }
            try await handler(value)
        }
        let id = register(base, KitConfirmer.hostConfirms ? handler : held)
        if id.rawValue != prefix + base, KitConfirmer.shared.warned.insert(id).inserted {
            warnings.append("\(id) asks for confirmation but shares its id with another control, so which one a press reaches depends on order; give it a distinct key")
        }
        return id
    }
}

/// The kit's own "press again" for hosts older than protocol 25, which don't
/// know `confirm`. Same window and wording as the host's `ActionConfirmer`,
/// but it can't redraw when the window passes: that is what the host adds.
@MainActor
final class KitConfirmer {
    static let shared = KitConfirmer()
    static let window: TimeInterval = 10
    /// The first protocol whose host confirms by itself.
    static let hostVersion = 25

    private var armed: (action: ActionID, text: String, at: Date)?
    var warned: Set<ActionID> = []

    /// Whether the host asks for confirmation itself. Unknown (no hello yet,
    /// as in a test driving views by hand) counts as yes.
    static var hostConfirms: Bool {
        (Stackbar.hostProtocol ?? StackbarProtocolVersion.current) >= hostVersion
    }

    /// A press of `action`: true when it is the second within the window.
    func pass(_ action: ActionID, text: String, now: Date = Date()) -> Bool {
        if let armed, armed.action == action, armed.text == text, now.timeIntervalSince(armed.at) < Self.window {
            self.armed = nil
            return true
        }
        armed = (action, text, now)
        Stackbar.hud("Press again within \(Int(Self.window)) s to \(text)")
        return false
    }

    func reset() {
        armed = nil
        warned = []
    }
}
