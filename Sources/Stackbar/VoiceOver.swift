#if os(macOS)
import AppKit

/// Spoken notices for what only shows as a change on screen: an action that
/// now asks for a second press, and the question going away.
@MainActor
enum VoiceOver {
    static func announce(_ text: String) {
        guard let app = NSApp else { return }
        NSAccessibility.post(element: app, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }
}
#endif
