import StackbarKit
import Foundation

/// A test plugin that does the least that reaches each system service and
/// surface the host provides: the clipboard trigger and paste, keepAwake from
/// a menu-bar click, the calendar, notification and alert buttons, row
/// previews and the settings surface. The host's side of each is tested here
/// without a first-party plugin's own behaviour on top.
@main
final class SystemFixture: StackbarPlugin {
    static let manifest = Manifest(
        id: "io.navbytes.stackbar.test.system",
        name: "System Fixture",
        surfaces: [.menuBar, .panel, .settings],
        triggers: [.launch, .clipboard],
        capabilities: [.clipboard, .power, .calendar]
    )

    var copies: [ClipboardItem] = []
    var meetings: [CalendarEvent] = []
    var awake = false
    @Stored("compact") var compact = false

    func refresh() async throws {
        meetings = try await Stackbar.calendarEvents(from: Date(), to: Date().addingTimeInterval(86_400))
        guard let item = try await Stackbar.clipboard(), item.text != nil, item.changeCount != copies.first?.changeCount else { return }
        copies.insert(item, at: 0)
    }

    var menuBar: ViewContent {
        Text(meetings.first?.title ?? "No meetings")
    }

    var menuBarClick: MenuBarAction? {
        awake
            ? MenuBarAction("Let the Mac sleep") {
                try await Stackbar.allowSleep()
                self.awake = false
            }
            : MenuBarAction("Keep awake") {
                try await Stackbar.keepAwake(reason: "clicked")
                self.awake = true
            }
    }

    var panel: ViewContent {
        List(copies) { item in
            let text = item.text ?? ""
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
            Row(text, key: "\(item.changeCount)")
                .preview(text: text, caption: "\(lines) lines")
                .action("Paste") { try await Stackbar.paste(item.contentID.map { .stored(id: $0) } ?? .text(text)) }
        }
        Button("Notify") { Stackbar.notify("Sync", actions: [NotificationAction("Join", url: "https://meet.google.com/abc-defg-hij")]) }
        Button("Alert") {
            Stackbar.alert("Board call", actions: [NotificationAction("Join", url: "https://acme.zoom.us/j/1"), NotificationAction("Call in", url: "tel:+16465588656,,123456789%23")])
        }
    }

    var settings: ViewContent {
        Toggle("Compact rows", isOn: compact) { self.compact = $0 }
    }
}
