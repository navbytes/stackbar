import Foundation
import StackbarProtocol

/// What the Settings window says about plugins, kept free of UI so it is
/// tested on Linux: a permission as an icon row, a plugin's status in words,
/// and the Privacy & Secrets overview across every plugin.
public enum SettingsPresentation {
    /// The kinds of access a plugin can have, in the order Settings lists them.
    public enum Access: String, CaseIterable, Sendable {
        case network, account, secret, files, run, clipboard, context, windows, keyboard, calendar, reminders, power, links, server, storage

        /// The heading on the Privacy & Secrets page.
        public var title: String {
            switch self {
            case .network: return "Network"
            case .account: return "Accounts"
            case .secret: return "Secrets"
            case .files: return "Files and Folders"
            case .run: return "Commands"
            case .clipboard: return "Clipboard"
            case .context: return "Selected Text"
            case .windows: return "Windows and Apps"
            case .keyboard: return "Keyboard"
            case .calendar: return "Calendar"
            case .reminders: return "Reminders"
            case .power: return "Power and Battery"
            case .links: return "Opening Links"
            case .server: return "Your Servers"
            case .storage: return "Extra Storage"
            }
        }

        /// An SF Symbol for the row's tile.
        public var symbol: String {
            switch self {
            case .network: return "network"
            case .account: return "person.crop.circle.fill"
            case .secret: return "key.fill"
            case .files: return "folder.fill"
            case .run: return "terminal.fill"
            case .clipboard: return "doc.on.clipboard.fill"
            case .context: return "text.cursor"
            case .windows: return "macwindow.on.rectangle"
            case .keyboard: return "keyboard.fill"
            case .calendar: return "calendar"
            case .reminders: return "checklist"
            case .power: return "bolt.fill"
            case .links: return "link"
            case .server: return "server.rack"
            case .storage: return "internaldrive.fill"
            }
        }

        /// The tile's colour, like System Settings' Privacy & Security rows.
        public var accent: Accent {
            switch self {
            case .network, .links: return .blue
            case .account: return .indigo
            case .secret: return .amber
            case .files, .storage: return .cyan
            case .run, .server: return .graphite
            case .clipboard: return .teal
            case .context: return .violet
            case .windows: return .pink
            case .keyboard: return .orange
            case .calendar: return .red
            case .reminders: return .orange
            case .power: return .green
            }
        }

        /// The kind behind a capability as an index lists it: the words
        /// `Capability.summary` wrote when the index was built.
        public init?(summary: String) {
            let prefixes: [(String, Access)] = [
                ("Connects to the server you enter", .server), ("Connects to", .network), ("Reads and writes", .files),
                ("Runs", .run), ("Reads the secret", .secret), ("Signs in to", .account), ("Reads everything you copy", .clipboard),
                ("Keeps the Mac awake", .power), ("Reads your calendar", .calendar), ("Reads and changes your reminders", .reminders), ("Reads the text you select", .context),
                ("Opens", .links), ("Stores up to", .storage), ("Sees which windows", .windows),
                ("Sees which apps", .windows), ("Listens for a key", .keyboard), ("Finds files", .files),
            ]
            guard let match = prefixes.first(where: { summary.hasPrefix($0.0) }) else { return nil }
            self = match.1
        }

        public init(_ capability: Capability) {
            switch capability {
            case .network: self = .network
            case .files: self = .files
            case .run: self = .run
            case .secret: self = .secret
            case .oauth: self = .account
            case .clipboard: self = .clipboard
            case .power: self = .power
            case .calendar: self = .calendar
            case .reminders: self = .reminders
            case .context: self = .context
            case .openURLs: self = .links
            case .storage: self = .storage
            case .userServer: self = .server
            case .windows, .apps, .menus: self = .windows
            case .fileSearch: self = .files
            case .systemActions: self = .power
            case .keyLayer, .textExpansion: self = .keyboard
            }
        }
    }

    /// One permission on a plugin's page: a tile, a title and the detail.
    public struct PermissionRow: Equatable, Sendable {
        public var access: Access
        public var title: String
        /// The capability in full words, as the approval sheet says it.
        public var detail: String
        /// Asked for and not yet allowed.
        public var isPending: Bool
    }

    /// A plugin's permissions, granted first, then those waiting for approval.
    /// Secrets are left out: the page shows them in their own section with
    /// Change and Clear.
    public static func permissions(granted: [Capability], pending: [Capability], resolver: CommandResolver = .standard) -> [PermissionRow] {
        func row(_ capability: Capability, pending: Bool) -> PermissionRow {
            let access = Access(capability)
            return PermissionRow(access: access, title: shortTitle(capability), detail: capability.summary(resolver: resolver), isPending: pending)
        }
        let shown = granted.filter { !pending.contains($0) }
        return (shown.map { row($0, pending: false) } + pending.map { row($0, pending: true) })
            .filter { $0.access != .secret }
    }

    /// The capability in a few words, for a row title.
    public static func shortTitle(_ capability: Capability) -> String {
        switch capability {
        case .network(let hosts): return hosts.isEmpty ? "Network" : hosts.joined(separator: ", ")
        case .files(let paths): return paths.joined(separator: ", ")
        case .run(let commands): return "Runs " + commands.joined(separator: ", ")
        case .secret(let name): return name
        case .oauth(let provider): return "Signs in to \(provider.name)"
        case .clipboard: return "Clipboard"
        case .power: return "Keeps the Mac awake"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .context: return "Selected text and app"
        case .openURLs(let schemes): return schemes.contains("*") ? "Opens any link" : "Opens " + schemes.map { "\($0):" }.joined(separator: ", ") + " links"
        case .storage(let megabytes): return "Up to \(megabytes) MB"
        case .userServer(let name): return name
        case .windows: return "Windows and apps"
        case .apps: return "Switches apps"
        case .keyLayer: return "Held-key shortcuts"
        case .fileSearch: return "Finds files by name"
        case .systemActions: return "Locks, sleeps and restarts the Mac"
        case .textExpansion: return "Expands keywords as you type"
        case .menus: return "Menu items of the app you're in"
        }
    }

    /// A plugin's status for its header and the sidebar dot.
    public struct Status: Equatable, Sendable {
        public enum Tone: Equatable, Sendable { case good, busy, attention, failed, off }
        public var text: String
        public var tone: Tone

        public init(text: String, tone: Tone) {
            self.text = text
            self.tone = tone
        }
    }

    public static func status(_ state: PluginSupervisor.State, isEnabled: Bool, waitingForApproval: Bool, missingSecrets: [String] = []) -> Status {
        guard isEnabled else { return Status(text: "Turned off", tone: .off) }
        if waitingForApproval { return Status(text: "Waiting for your approval", tone: .attention) }
        switch state {
        case .running:
            if let secret = missingSecrets.first { return Status(text: "Needs \(secret)", tone: .attention) }
            return Status(text: "Running", tone: .good)
        case .starting: return Status(text: "Starting…", tone: .busy)
        case .restarting(let attempt, let seconds):
            return Status(text: "Restarting in \(Int(seconds.rounded()))s (attempt \(attempt))", tone: .busy)
        case .failed(let reason): return Status(text: "Stopped: \(reason)", tone: .failed)
        case .stopped: return Status(text: "Stopped", tone: .off)
        }
    }

    /// One plugin as the Privacy & Secrets overview sees it.
    public struct PluginAccess: Equatable, Sendable {
        public var id: String
        public var name: String
        public var granted: [Capability]
        public var pending: [Capability]

        public init(id: String, name: String, granted: [Capability], pending: [Capability] = []) {
            self.id = id
            self.name = name
            self.granted = granted
            self.pending = pending
        }
    }

    /// One heading on the Privacy & Secrets page and who has that access.
    public struct AccessGroup: Equatable, Sendable {
        public struct Holder: Equatable, Sendable {
            public var pluginID: String
            public var pluginName: String
            public var detail: String
            public var isPending: Bool
        }

        public var access: Access
        public var holders: [Holder]
    }

    /// Every kind of access some plugin has or asks for, in `Access` order,
    /// each with its plugins by name. Kinds nobody holds are left out.
    public static func overview(_ plugins: [PluginAccess]) -> [AccessGroup] {
        var holders: [Access: [AccessGroup.Holder]] = [:]
        for plugin in plugins {
            let granted = plugin.granted.filter { !plugin.pending.contains($0) }
            for (capability, pending) in granted.map({ ($0, false) }) + plugin.pending.map({ ($0, true) }) {
                holders[Access(capability), default: []].append(.init(pluginID: plugin.id, pluginName: plugin.name, detail: shortTitle(capability), isPending: pending))
            }
        }
        return Access.allCases.compactMap { access in
            guard let list = holders[access] else { return nil }
            let sorted = list.sorted { ($0.pluginName.localizedLowercase, $0.detail) < ($1.pluginName.localizedLowercase, $1.detail) }
            return AccessGroup(access: access, holders: sorted)
        }
    }

    /// A secret and the plugins that use it, by name.
    public struct SecretUse: Equatable, Sendable {
        public var secret: String
        public var plugins: [String]
    }

    /// Every declared secret with its plugins, for the overview.
    public static func secrets(_ plugins: [(name: String, secrets: [String])]) -> [SecretUse] {
        var users: [String: [String]] = [:]
        for plugin in plugins {
            for secret in Set(plugin.secrets) { users[secret, default: []].append(plugin.name) }
        }
        return users.keys.sorted().map { SecretUse(secret: $0, plugins: users[$0]!.sorted { $0.localizedLowercase < $1.localizedLowercase }) }
    }
}
