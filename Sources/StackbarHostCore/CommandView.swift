import Foundation
import StackbarProtocol

/// One open view command, as the host keeps it: what to send the plugin as
/// the query changes, which trees to show, and what a restart, a stop or a
/// submitted form means. The palette (`CommandViewModel`) and headless runs
/// (`PluginSession`, behind `stackbarctl render` and the MCP servers) drive
/// the same rules, so what an author checks headless is what the palette
/// does.
///
/// It holds no process: each input returns the messages to send, in order,
/// and the caller sends them.
public struct CommandView: Sendable {
    /// A message for the plugin, in the order it must arrive.
    public enum Send: Equatable, Sendable {
        case open(seq: Int, query: CommandQuery)
        case update(seq: Int, query: CommandQuery)
        case event(ActionID, EventValue?)
        case close
    }

    /// What a tree that arrived did.
    public struct Received: Equatable, Sendable {
        /// It is newer than what is shown, and replaces it.
        public var shown = false
        /// It answered a submitted form without errors: the palette closes.
        public var finished = false
        public var sends: [Send] = []
    }

    public let session: Int
    public let pluginName: String
    private var state: ViewSessionState
    /// The newest query, also while nothing can be sent.
    public private(set) var query: CommandQuery
    public private(set) var problem: String?
    /// Counts the trees shown.
    public private(set) var answers = 0
    public private(set) var isClosed = false
    /// The plugin restarted; the view opens again once it runs.
    public private(set) var isWaitingForPlugin = false
    /// Stopped or failed: nothing will answer.
    public private(set) var isStopped = false
    private var submitting = false

    public init(session: Int, pluginName: String, query: CommandQuery) {
        self.session = session
        self.pluginName = pluginName
        self.query = query
        state = ViewSessionState(session: session, query: query)
    }

    public var root: ViewNode? { state.root }
    /// Waiting for the plugin to answer the newest query.
    public var isSearching: Bool { isWaitingForPlugin || (!isStopped && !isClosed && state.isSearching) }
    /// Whether an action can reach the plugin now. After a close the plugin
    /// has no handler for the view's actions.
    public var canAct: Bool { !isClosed && !isWaitingForPlugin && !isStopped }

    /// The first message for the view.
    public mutating func open() -> [Send] {
        [state.open()].map(Self.send)
    }

    /// The query changed. While the plugin restarts or is stopped, the
    /// newest query goes out when the view opens again; while one is being
    /// answered, the newest goes out after it.
    public mutating func change(_ query: CommandQuery) -> [Send] {
        self.query = query
        guard canAct, let next = state.change(query) else { return [] }
        return [Self.send(next)]
    }

    /// The plugin sent a tree for this view.
    public mutating func received(seq: Int, root: ViewNode) -> Received {
        guard !isClosed else { return Received() }
        let (show, next) = state.received(seq: seq, root: root)
        var result = Received(shown: show, sends: next.map { [Self.send($0)] } ?? [])
        guard show else { return result }
        answers += 1
        problem = nil
        if submitting {
            submitting = false
            result.finished = !root.hasFormErrors
        }
        return result
    }

    /// An action inside the view. A submitted form (`.fields`) waits for its
    /// answer, which says whether it finished.
    public mutating func perform(_ action: ActionID, _ value: EventValue? = nil) -> [Send] {
        guard canAct else { return [] }
        if case .fields = value { submitting = true }
        return [.event(action, value)]
    }

    /// The plugin's process changed state. Restarting: the view went with
    /// the old process, so it waits and opens again with the newest query
    /// once the plugin runs. Failed or stopped: it says so, instead of
    /// searching forever.
    public mutating func pluginState(_ plugin: PluginSupervisor.State) -> [Send] {
        guard !isClosed else { return [] }
        switch plugin {
        case .restarting:
            isWaitingForPlugin = true
            isStopped = false
            submitting = false
            problem = "\(pluginName) restarted; reconnecting…"
        case .running:
            guard isWaitingForPlugin || isStopped else { return [] }
            isWaitingForPlugin = false
            isStopped = false
            problem = nil
            return [Self.send(state.reopen(query))]
        case .failed(let reason):
            stop("\(pluginName) stopped: \(reason)")
        case .stopped:
            stop("\(pluginName) is turned off")
        case .starting:
            break
        }
        return []
    }

    /// Closes the view; nothing more goes to the plugin after the close.
    public mutating func close() -> [Send] {
        guard !isClosed else { return [] }
        isClosed = true
        return [.close]
    }

    private mutating func stop(_ message: String) {
        isWaitingForPlugin = false
        isStopped = true
        submitting = false
        problem = message
    }

    private static func send(_ send: ViewSessionState.Send) -> Send {
        switch send {
        case .open(let seq, let query): return .open(seq: seq, query: query)
        case .update(let seq, let query): return .update(seq: seq, query: query)
        }
    }
}
