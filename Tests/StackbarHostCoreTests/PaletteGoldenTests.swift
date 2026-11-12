import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// What a new user's typing puts first, against a realistic Mac: the apps a
/// macOS 26 install and a developer add, and the commands of the store's
/// everyday plugins. Each case is what someone switching from Spotlight or
/// Raycast expects after a few letters and Return
/// (openspec/changes/trust-first, task 2.1).
///
/// A change to the ranker that moves one of these is a change users feel:
/// fix the ranker, or change the case here on purpose and say why.
final class PaletteGoldenTests: XCTestCase {
    private static let apps = [
        "Safari", "Mail", "Messages", "Maps", "Music", "Notes", "Calendar", "Contacts", "Reminders", "Photos",
        "Preview", "System Settings", "Terminal", "Finder", "App Store", "Activity Monitor", "Xcode",
        "Visual Studio Code", "Slack", "Spotify", "Google Chrome", "Firefox", "zoom.us", "Calculator", "TextEdit",
        "Keynote", "Pages", "Numbers", "FaceTime", "Shortcuts", "Screenshot", "Disk Utility", "Console",
        "Font Book", "Books", "Podcasts", "TV", "News", "Stocks", "Weather", "Clock", "Passwords", "Photo Booth",
        "QuickTime Player", "Automator", "Script Editor", "Keychain Access", "iPhone Mirroring", "Freeform",
        "Home", "Find My", "Notion", "Figma", "Docker Desktop", "1Password", "Arc", "Ghostty", "Cursor",
        "Microsoft Word", "Microsoft Excel", "Microsoft Outlook", "Microsoft Teams", "Discord", "WhatsApp",
        "Signal", "Linear", "Obsidian", "Postman", "Simulator", "Instruments", "Image Playground", "Games",
        "Journal", "Phone", "Migration Assistant", "Bluetooth File Exchange", "Grapher", "Stickies", "Chess",
        "Dictionary", "Image Capture", "Audio MIDI Setup", "Boot Camp Assistant", "Stackbar",
    ]

    /// Every command the store's plugins declare, with their real subtitles
    /// and keywords (scripts/palette-corpus.py; rerun it when plugins change
    /// their words).
    private struct Corpus: Decodable {
        struct Command: Decodable {
            var plugin: String
            var id: String
            var title: String
            var subtitle: String?
            var keywords: [String]
        }
        var commands: [Command]
    }

    /// Query → the title that must come first.
    private static let golden: [(String, String)] = [
        // Spotlight habits: an app by its first letters.
        ("saf", "Safari"), ("safari", "Safari"), ("mai", "Mail"), ("mes", "Messages"), ("cal", "Calendar"),
        ("calc", "Calculate"), ("calculator", "Calculator"), ("term", "Terminal"), ("fin", "Finder"), ("xco", "Xcode"), ("sla", "Slack"),
        ("spo", "Spotify"), ("chrome", "Google Chrome"), ("fire", "Firefox"), ("zoom", "zoom.us"),
        ("note", "Notes"), ("remi", "Reminders"), ("phot", "Photos"), ("prev", "Preview"),
        ("system settings", "System Settings"), ("act", "Activity Monitor"), ("activity", "Activity Monitor"),
        ("disk", "Disk Utility"), ("key", "Keynote"), ("keych", "Keychain Access"), ("face", "FaceTime"),
        ("short", "Shortcuts"), ("app store", "App Store"), ("microsoft w", "Microsoft Word"), ("excel", "Microsoft Excel"),
        ("outl", "Microsoft Outlook"), ("teams", "Microsoft Teams"), ("disc", "Discord"), ("obs", "Obsidian"),
        ("1pa", "1Password"), ("ghost", "Ghostty"), ("figma", "Figma"), ("music", "Music"), ("maps", "Maps"),
        ("tv", "TV"), ("arc", "Arc"), ("home", "Home"), ("books", "Books"), ("clock", "Clock"),
        ("passw", "Passwords"), ("stick", "Stickies"), ("stackbar", "Stackbar"),
        // Initials, as Raycast and Alfred take them.
        ("vsc", "Visual Studio Code"), ("du", "Disk Utility"),
        ("qtp", "QuickTime Player"),
        // Words inside a name.
        ("code", "Visual Studio Code"), ("monitor", "Activity Monitor"), ("mirroring", "iPhone Mirroring"),
        // Raycast habits: commands by their verb or noun.
        ("lock", "Lock Screen"), ("sleep", "Sleep"), ("restart", "Restart"), ("shut", "Shut Down"),
        ("log out", "Log Out"), ("trash", "Empty Trash"), ("empty", "Empty Trash"), ("dark", "Toggle Dark Mode"),
        ("eject", "Eject All Disks"), ("clipboard", "Clipboard History"), ("clip", "Clipboard History"),
        ("search snip", "Search Snippets"), ("create snip", "Create Snippet"), ("search quick", "Search Quicklinks"),
        ("search emoji", "Search Emoji"), ("left half", "Left Half"), ("right", "Right Half"), ("maxi", "Maximize"),
        ("switch windows", "Switch Windows"), ("menu items", "Search Menu Items"), ("search files", "Search Files"),
        ("create note", "Create Note"), ("todo", "Add a Todo"), ("ask", "Ask AI"), ("ask ai", "Ask AI"),
        ("kill proc", "Kill Process"), ("kill port", "Kill Port"), ("ports", "Listening Ports"),
        ("docker desk", "Docker Desktop"), ("containers", "Docker Containers"), ("pull requests", "Search Pull Requests"),
        ("review", "Review Queue"), ("github inbox", "GitHub Inbox"), ("recent", "Search Recent Projects"),
        ("tabs", "Search Browser Tabs"), ("bookmarks", "Search Bookmarks"), ("pick color", "Pick Color"),
        ("define", "Define Word"), ("next track", "Next Track"), ("play", "Play or Pause Music"),
        ("timers", "Show Timers"), ("awake", "Keep Awake For…"), ("join next", "Join Next Meeting"),
        ("scripts", "Script Commands"), ("settings", "Stackbar Settings"), ("system set", "System Settings"), ("stackbar settings", "Stackbar Settings"),
        ("store", "Plugin Store"), ("app store", "App Store"), ("hotkeys", "Commands & Hotkeys"),
        // A plugin's keyword or subtitle never beats an app or command with
        // the word in its name (each of these went to a keyword before).
        ("chrome", "Google Chrome"), ("zoom", "zoom.us"), ("note", "Notes"), ("activity", "Activity Monitor"),
        ("disk", "Disk Utility"), ("teams", "Microsoft Teams"), ("monitor", "Activity Monitor"), ("sleep", "Sleep"),
        // Space- and case-blind.
        ("SAFARI", "Safari"), ("  saf", "Safari"), ("visualstudio", "Visual Studio Code"),
    ]

    private func corpus() throws -> [PaletteIndex.Entry] {
        var entries = Self.apps.map { title -> PaletteIndex.Entry in
            var entry = PaletteIndex.Entry(pluginID: "io.navbytes.stackbar.plugins.applications", pluginName: "Applications",
                                           title: title, kind: .action(ActionID("open/\(title)"), value: nil))
            entry.rankKey = "io.navbytes.stackbar.plugins.applications|row|search|\(title)"
            return entry
        }
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/palette-corpus.json")
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: file))
        for command in corpus.commands {
            let name = command.plugin.split(separator: ".").last.map(String.init) ?? command.plugin
            entries.append(PaletteIndex.Entry(pluginID: command.plugin, pluginName: name, title: command.title, subtitle: command.subtitle,
                                              kind: .command(CommandSpec(id: command.id, title: command.title)), keywords: command.keywords))
        }
        return entries + PaletteIndex.appEntries
    }

    private func top(_ entries: [PaletteIndex.Entry], _ query: String) -> [String] {
        let ranker = PaletteRanker(query: query, usage: nil, picks: nil)
        return entries.enumerated()
            .compactMap { offset, entry in ranker.score(entry).map { (entry.title, $0, offset) } }
            .sorted { ($0.1, -$0.2) > ($1.1, -$1.2) }
            .prefix(3)
            .map(\.0)
    }

    func testANewUsersTypingPutsTheExpectedRowFirst() throws {
        let entries = try corpus()
        var misses: [String] = []
        for (query, expected) in Self.golden {
            let found = top(entries, query)
            if found.first != expected {
                misses.append("\"\(query)\": expected \(expected), got \(found.joined(separator: " | "))")
            }
        }
        XCTAssert(misses.isEmpty, "\(misses.count) of \(Self.golden.count) golden queries missed:\n" + misses.joined(separator: "\n"))
    }

    func testEveryGoldenAnswerIsInTheCorpus() throws {
        let titles = Set(try corpus().map(\.title))
        for (query, expected) in Self.golden {
            XCTAssert(titles.contains(expected), "\"\(query)\" expects \(expected), which the corpus lacks")
        }
    }

    /// Two picks of the same row for the same text make it lead, from the
    /// golden starting point: what someone who prefers it teaches in a day.
    func testPicksOverrideTheDefault() throws {
        let entries = try corpus()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let picks = PalettePicks(file: nil) { now }
        let chosen = try XCTUnwrap(entries.first { $0.title == "Clipboard History" })
        XCTAssertEqual(top(entries, "c").first == "Clipboard History", false, "not first before any pick")
        picks.record(query: "c", id: chosen.learnID)
        picks.record(query: "c", id: chosen.learnID)
        let ranker = PaletteRanker(query: "c", usage: nil, picks: picks)
        let first = entries.enumerated()
            .compactMap { offset, entry in ranker.score(entry).map { (entry.title, $0, offset) } }
            .max { ($0.1, -$0.2) < ($1.1, -$1.2) }?.0
        XCTAssertEqual(first, "Clipboard History")
    }
}
