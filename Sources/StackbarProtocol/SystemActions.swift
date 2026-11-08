/// Things a plugin with `.systemActions` can ask the Mac to do through
/// `Stackbar.system(_:)`, the commands Raycast and Alfred ship as "System".
/// Protocol 18.
public enum SystemAction: String, Codable, CaseIterable, Sendable {
    case lockScreen
    case sleep
    case sleepDisplays
    case startScreenSaver
    case restart
    case shutDown
    case logOut
    case emptyTrash
    case toggleDarkMode
    case hideOtherApps
    case quitOtherApps
    case ejectDisks

    /// The action in a few words, for labels and the host log.
    public var title: String {
        switch self {
        case .lockScreen: return "Lock Screen"
        case .sleep: return "Sleep"
        case .sleepDisplays: return "Sleep Displays"
        case .startScreenSaver: return "Start Screen Saver"
        case .restart: return "Restart"
        case .shutDown: return "Shut Down"
        case .logOut: return "Log Out"
        case .emptyTrash: return "Empty Trash"
        case .toggleDarkMode: return "Toggle Dark Mode"
        case .hideOtherApps: return "Hide Other Apps"
        case .quitOtherApps: return "Quit Other Apps"
        case .ejectDisks: return "Eject All Disks"
        }
    }

    /// Whether the action loses the user's work or data if run by mistake.
    /// Give the control that runs one `confirm` (protocol 25), and the host
    /// asks for a second press before the plugin hears of it. The call itself
    /// runs as asked: by then the user has confirmed.
    public var isDestructive: Bool {
        switch self {
        case .restart, .shutDown, .logOut, .emptyTrash, .quitOtherApps: return true
        case .lockScreen, .sleep, .sleepDisplays, .startScreenSaver, .toggleDarkMode, .hideOtherApps, .ejectDisks: return false
        }
    }
}
