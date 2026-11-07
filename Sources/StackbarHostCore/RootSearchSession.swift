import Foundation
import StackbarProtocol

/// A live view of a `.rootSearch()` command, as `RootSearchSession` sees it.
/// The app's command view model is one; tests use a fake.
@MainActor
public protocol RootSearchView: AnyObject {
    var entry: CommandRegistry.Entry { get }
    /// The text it searches. Setting it sends the new text to the plugin.
    var query: String { get set }
    /// Waiting for the plugin to answer the current text.
    var isSearching: Bool { get }
    /// Stopped or failed: nothing will answer.
    var isStopped: Bool { get }
    var isClosed: Bool { get }
    /// The newest tree the plugin answered with.
    var root: ViewNode? { get }
    /// Counts the trees shown, so rows are filtered once per answer.
    var answers: Int { get }
    /// When the newest answer arrived.
    var answeredAt: Date? { get }
    func close()
}

/// The palette's root search: the views of `.rootSearch()` commands that are
/// open while the user types at the root, all fed the same text, and the
/// rows each shows.
///
/// It decides which views open, stay and close as the text changes (by
/// `RootSearchGate` and `RootSearchBudget`), times each answer from when
/// the text went out to when the answer arrived, and runs a row from the
/// freshest answer. The palette only draws what it reports.
@MainActor
public final class RootSearchSession<View: RootSearchView> {
    /// Opens a view of the command with this text; nil when it couldn't.
    public typealias Opener = (CommandRegistry.Entry, String) async -> View?

    /// What to do with Return on a root row: run this action now, or the
    /// row went away while the plugin answered newer text.
    public enum Activation: Equatable {
        case perform(ActionRef)
        case gone
    }

    public let budget: RootSearchBudget
    /// The least text that is searched.
    public static var minimumLength: Int { 2 }

    public private(set) var views: [CommandKey: View] = [:]
    /// Bumped when a view opens or closes, so the root reads the views again.
    public private(set) var revision = 0 { didSet { onChange?() } }
    /// Runs when `revision` moves, for a UI that observes its own state.
    public var onChange: (() -> Void)?
    private var opening: Set<CommandKey> = []
    /// Fed new text and not answered yet, since when.
    private var fedAt: [CommandKey: Date] = [:]
    /// Each view's rows, filtered once per answer and text.
    private var filtered: [CommandKey: (answers: Int, query: String, rows: [RowNode])] = [:]
    /// Moves whenever what `rows()` reports could differ from the last call:
    /// a view opened, closed or stopped, or one filtered a new answer. A
    /// cache of what was built from the rows keys on this instead of
    /// comparing the rows themselves.
    public private(set) var rowsStamp = 0
    private var shown: Set<CommandKey> = []
    private var text: String?
    private var accepts: (CommandRegistry.Entry, String) -> Bool = { _, _ in false }
    private let now: () -> Date

    public init(budget: RootSearchBudget, now: @escaping () -> Date = Date.init) {
        self.budget = budget
        self.now = now
    }

    /// The text root search is asked about: what is typed at the root, when
    /// it is long enough. Nil inside a command.
    public static func searchText(_ query: String, atRoot: Bool) -> String? {
        let text = query.trimmingCharacters(in: .whitespaces)
        return atRoot && text.count >= minimumLength ? text : nil
    }

    /// Feeds `text` (nil closes everything) to the commands `accepts` takes
    /// for it and the budget hasn't benched. Views that no longer qualify
    /// close, so their rows for older text don't linger. `canOpen` says
    /// whether a command's plugin is running: root search never starts one.
    public func feed(_ text: String?, commands: [CommandRegistry.Entry], accepts: @escaping (CommandRegistry.Entry, String) -> Bool,
                     canOpen: (CommandRegistry.Entry) -> Bool, open: @escaping Opener) {
        self.text = text
        self.accepts = accepts
        guard let text else {
            closeAll()
            return
        }
        let wanted = commands.filter { accepts($0, text) && !budget.isBenched($0.key, now: now()) }
        let keys = Set(wanted.map(\.key))
        for (key, view) in views where !keys.contains(key) {
            drop(key, view)
        }
        for entry in wanted {
            if let view = views[entry.key] {
                if view.query != text {
                    let moment = now()
                    // New text while the last is still unanswered: a plugin
                    // that never answers is never timed by `timeAnswers`, so
                    // the wait so far counts here, and benches it in time.
                    if view.isSearching, let asked = fedAt[entry.key], moment.timeIntervalSince(asked) > budget.limit {
                        budget.record(entry.key, took: moment.timeIntervalSince(asked), now: moment)
                    }
                    fedAt[entry.key] = moment
                    view.query = text
                }
                continue
            }
            guard !opening.contains(entry.key), canOpen(entry) else { continue }
            opening.insert(entry.key)
            let key = entry.key
            Task { @MainActor in
                let view = await open(entry, text)
                self.opening.remove(key)
                guard let view else { return }
                self.opened(view, key: key)
            }
        }
    }

    /// A view finished opening. The text may have moved on meanwhile: it is
    /// kept only while the root is open, its pattern still matches and it
    /// isn't benched.
    func opened(_ view: View, key: CommandKey) {
        guard let current = text, views[key] == nil, accepts(view.entry, current), !budget.isBenched(key, now: now()) else {
            view.close()
            return
        }
        view.query = current
        views[key] = view
        rowsStamp += 1
        // Timed from here: waiting for the plugin to start isn't the plugin
        // being slow, and shouldn't bench it.
        fedAt[key] = now()
        revision += 1
    }

    public func closeAll() {
        for (key, view) in views { drop(key, view) }
        opening = []
    }

    private func drop(_ key: CommandKey, _ view: View) {
        view.close()
        views[key] = nil
        fedAt[key] = nil
        filtered[key] = nil
        rowsStamp += 1
        revision += 1
    }

    /// Notes the answers that arrived since the last call, for the budget:
    /// each took from when its text went out to when it arrived.
    public func timeAnswers() {
        for (key, view) in views where !view.isSearching {
            guard let fed = fedAt.removeValue(forKey: key) else { continue }
            let arrived = view.answeredAt.map { max($0, fed) } ?? now()
            budget.record(key, took: arrived.timeIntervalSince(fed), now: now())
        }
    }

    /// What each open view shows now, filtered by its text. Cheap to call
    /// on every redraw: each view's rows are filtered once per answer.
    public func rows() -> [PaletteRoot.PluginRows] {
        guard text != nil else { return [] }
        timeAnswers()
        let live = views.values.filter { !$0.isStopped }
        let keys = Set(live.map { $0.entry.key })
        if keys != shown {
            shown = keys
            rowsStamp += 1
        }
        return live.map { PaletteRoot.PluginRows(command: $0.entry, rows: rows(of: $0)) }
    }

    /// A view's rows for its text, from its newest answer.
    public func rows(of view: View) -> [RowNode] {
        let key = view.entry.key
        if let known = filtered[key], known.answers == view.answers, known.query == view.query { return known.rows }
        let rows = Self.rows(in: view.root, query: view.query)
        if views[key] === view {
            filtered[key] = (view.answers, view.query, rows)
            rowsStamp += 1
        }
        return rows
    }

    /// The rows of a tree, filtered by `query` as the palette lists them.
    public nonisolated static func rows(in root: ViewNode?, query: String) -> [RowNode] {
        guard let root, let items = RowFilter.items(in: root, query: query) else { return [] }
        return items.compactMap { if case .row(let row) = $0 { return row } else { return nil } }
    }

    /// Return on a root row with this key, whose shown action was `action`.
    /// While the view is still answering newer text, the row on screen is
    /// from the older answer, and the plugin drops actions of rows it no
    /// longer shows. So this waits for the answer (`wait` at most) and
    /// runs the same row from it, with the action of the same title. When
    /// there is still no answer, the row as shown is the best there is.
    /// Nil when the view closed meanwhile.
    public func activation(of view: View, key: String, action: ActionRef, wait: Duration = .seconds(1)) async -> Activation? {
        guard view.isSearching else { return .perform(action) }
        let deadline = ContinuousClock.now.advanced(by: wait)
        while view.isSearching, !view.isClosed, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard !view.isClosed else { return nil }
        let fresh = rows(of: view).first { $0.key == key }
        if let ref = fresh?.actions.first(where: { $0.title == action.title }) ?? fresh?.actions.first { return .perform(ref) }
        return view.isSearching ? .perform(action) : .gone
    }
}
