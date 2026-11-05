#if os(macOS)
import AppKit
import ApplicationServices
import StackbarHostCore
import StackbarProtocol

extension MacSystem {
    func menuItems() async throws -> MenuSnapshot {
        try await MainActor.run {
            guard MacWindows.isTrusted() else { throw MacMenus.untrusted }
            guard let app = userApp() else { throw SystemServiceError("there is no app in front to read menus from") }
            return MacMenus.read(app)
        }
    }

    func pressMenuItem(appID: String, path: [String]) async throws {
        try await MainActor.run {
            guard MacWindows.isTrusted() else { throw MacMenus.untrusted }
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: appID).first(where: { !$0.isTerminated }) else {
                throw SystemServiceError("\(appID) isn't running")
            }
            app.activate()
            try MacMenus.press(path, in: app)
        }
    }

    /// The app the user is working in: the front one, or the one before
    /// Stackbar when the palette or a panel is in front.
    @MainActor fileprivate func userApp() -> NSRunningApplication? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        return frontmost?.processIdentifier == getpid() ? previousApp : frontmost
    }
}

/// An app's menu bar through Accessibility: the same tree VoiceOver reads.
/// Reading walks every menu (most apps fill theirs in up front; a few build
/// submenus only when opened, and those come back empty).
@MainActor
enum MacMenus {
    nonisolated static let untrusted = SystemServiceError("Stackbar needs Accessibility access to read menus: System Settings > Privacy & Security > Accessibility")

    static func read(_ app: NSRunningApplication) -> MenuSnapshot {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)
        var items: [MenuItemInfo] = []
        // The first menu bar item is the Apple menu, the same in every app.
        for top in topMenus(of: element).dropFirst() {
            guard let title = string(top, kAXTitleAttribute), !title.isEmpty else { continue }
            walk(top, path: [title], depth: 1, into: &items)
            if items.count >= MenuSnapshot.maxItems { break }
        }
        let id = app.bundleIdentifier ?? ""
        return MenuSnapshot(appID: id, appName: app.localizedName ?? id, items: items)
    }

    static func press(_ path: [String], in app: NSRunningApplication) throws {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)
        guard let first = path.first, var current = topMenus(of: element).dropFirst().first(where: { string($0, kAXTitleAttribute) == first }) else {
            throw SystemServiceError("\(app.localizedName ?? "The app") has no \(path.first ?? "") menu")
        }
        for title in path.dropFirst() {
            guard let next = children(of: current).first(where: { string($0, kAXTitleAttribute) == title }) else {
                throw SystemServiceError("no menu item \(path.joined(separator: " > "))")
            }
            current = next
        }
        guard bool(current, kAXEnabledAttribute) else { throw SystemServiceError("\(path.last ?? "That item") is dimmed right now") }
        guard AXUIElementPerformAction(current, kAXPressAction as CFString) == .success else {
            throw SystemServiceError("\(path.last ?? "That item") couldn't be chosen")
        }
    }

    private static func topMenus(of app: AXUIElement) -> [AXUIElement] {
        guard let bar = copy(app, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [] }
        // swiftlint:disable:next force_cast
        return elements(bar as! AXUIElement, kAXChildrenAttribute)
    }

    /// A menu bar item or a menu item holds one menu, which holds the items.
    private static func children(of item: AXUIElement) -> [AXUIElement] {
        elements(item, kAXChildrenAttribute).flatMap { child in
            string(child, kAXRoleAttribute) == kAXMenuRole ? elements(child, kAXChildrenAttribute) : [child]
        }
    }

    private static func walk(_ item: AXUIElement, path: [String], depth: Int, into items: inout [MenuItemInfo]) {
        for child in children(of: item) {
            guard items.count < MenuSnapshot.maxItems else { return }
            guard let title = string(child, kAXTitleAttribute), !title.isEmpty else { continue }
            let childPath = path + [title]
            let submenu = elements(child, kAXChildrenAttribute)
            if !submenu.isEmpty {
                if depth < MenuSnapshot.maxDepth { walk(child, path: childPath, depth: depth + 1, into: &items) }
                continue
            }
            let character = string(child, kAXMenuItemCmdCharAttribute)
            let modifiers = (copy(child, kAXMenuItemCmdModifiersAttribute) as? Int) ?? 0
            let checked = string(child, kAXMenuItemMarkCharAttribute).map { !$0.isEmpty } ?? false
            items.append(MenuItemInfo(path: childPath, shortcut: MenuSnapshot.shortcut(character: character, modifiers: modifiers),
                                      isEnabled: bool(child, kAXEnabledAttribute), isChecked: checked))
        }
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        (copy(element, attribute) as? [AXUIElement]) ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        (copy(element, attribute) as? Bool) ?? false
    }
}
#endif
