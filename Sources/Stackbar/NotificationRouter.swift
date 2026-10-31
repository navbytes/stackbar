#if os(macOS)
import AppKit
import UserNotifications
import StackbarHostCore
import StackbarProtocol

/// Posts plugin notifications with their buttons and handles the clicks: a
/// button opens its URL, the notification itself opens the plugin's panel.
/// Buttons work after the plugin has moved on, because the host holds the
/// URLs, not the plugin.
@MainActor
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()
    private var categories: [String: UNNotificationCategory] = [:]

    func post(_ note: HostNotification) {
        let content = UNMutableNotificationContent()
        content.title = note.title
        content.subtitle = note.pluginName
        if let body = note.body { content.body = body }
        var info: [String: Any] = ["pluginID": note.pluginID]
        if !note.actions.isEmpty {
            let id = "stackbar.actions." + note.actions.map(\.title).joined(separator: "|")
            if categories[id] == nil {
                let actions = note.actions.enumerated().map { index, action in
                    UNNotificationAction(identifier: "action-\(index)", title: action.title, options: [.foreground])
                }
                categories[id] = UNNotificationCategory(identifier: id, actions: actions, intentIdentifiers: [])
                UNUserNotificationCenter.current().setNotificationCategories(Set(categories.values))
            }
            content.categoryIdentifier = id
            info["urls"] = note.actions.map(\.url)
        }
        content.userInfo = info
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let pluginID = info["pluginID"] as? String
        let urls = info["urls"] as? [String] ?? []
        await MainActor.run { Self.handle(action: action, pluginID: pluginID, urls: urls) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    private static func handle(action: String, pluginID: String?, urls: [String]) {
        if action.hasPrefix("action-"), let index = Int(action.dropFirst("action-".count)), urls.indices.contains(index) {
            guard let url = URL(string: urls[index]), let scheme = url.scheme?.lowercased(), HostServices.openableSchemes.contains(scheme) else { return }
            NSWorkspace.shared.open(url)
        } else if action == UNNotificationDefaultActionIdentifier, let pluginID {
            AppDelegate.shared?.showPanel(pluginID: pluginID)
        }
    }
}
#endif
