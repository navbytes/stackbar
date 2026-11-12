/// The secrets a plugin read while they were unset: what its "Needs X"
/// status, the lock on its menu-bar item and the panel's prompt show.
///
/// A plugin flags one by reading it (`Stackbar.secret`) while it is empty.
/// What the plugin needs can change without a save, though: PR Cockpit's
/// "Sign in with gh" stops it reading `GITHUB_TOKEN` at all. So the flags
/// are forgotten whenever what the plugin needs may have changed (a press on
/// its Settings page, a restart, a rebuild, turning it off), and a secret it
/// still needs is flagged again on its next read. Before, only saving the
/// secret cleared it, and the mark stayed until Stackbar was relaunched.
public struct MissingSecrets: Equatable, Sendable {
    public private(set) var names: [String] = []

    public enum Event: Equatable, Sendable {
        /// The plugin read this secret while it was unset.
        case asked(String)
        /// The user saved a value for it.
        case saved(String)
        /// Something that may change what the plugin needs.
        case settingsChanged, restarted, reloaded, turnedOff
    }

    public init() {}

    /// Applies an event; true when the names changed.
    @discardableResult
    public mutating func note(_ event: Event) -> Bool {
        let before = names
        switch event {
        case .asked(let name):
            if !names.contains(name) { names.append(name) }
        case .saved(let name):
            names.removeAll { $0 == name }
        case .settingsChanged, .restarted, .reloaded, .turnedOff:
            names = []
        }
        return names != before
    }
}
