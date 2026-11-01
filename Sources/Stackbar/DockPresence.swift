#if os(macOS)
import AppKit

/// Shows Stackbar in the Dock and ⌘Tab while one of its windows is open
/// (a plugin window or Settings), so a window behind others can be found
/// like any app's; it goes back to menu-bar only when the last one closes.
/// "Show in the Dock while a window is open" in Settings turns it off.
@MainActor
final class DockPresence {
    static let shared = DockPresence()
    static let settingKey = "dockWhileWindowsOpen"

    private var windows: Set<ObjectIdentifier> = []
    private var observers: [ObjectIdentifier: NSObjectProtocol] = [:]

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: settingKey)
            shared.update()
        }
    }

    /// Counts `window` until it closes.
    func track(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        guard !windows.contains(id) else { return update() }
        windows.insert(id)
        observers[id] = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.untrack(id) }
        }
        update()
    }

    private func untrack(_ id: ObjectIdentifier) {
        windows.remove(id)
        if let observer = observers.removeValue(forKey: id) { NotificationCenter.default.removeObserver(observer) }
        update()
    }

    func update() {
        let wanted: NSApplication.ActivationPolicy = Self.enabled && !windows.isEmpty ? .regular : .accessory
        guard NSApp.activationPolicy() != wanted else { return }
        NSApp.setActivationPolicy(wanted)
        // Leaving the Dock hands focus to another app; don't steal it back.
        if wanted == .regular { NSApp.activate() }
    }

    /// The menus a regular app needs: Quit, Settings, Edit (so ⌘C and ⌘V
    /// work in text fields) and Window (⌘W, ⌘M and the window list).
    static func installMainMenu(settings: Selector, target: AnyObject) {
        let main = NSMenu()
        let appMenu = NSMenu(title: "Stackbar")
        appMenu.addItem(withTitle: "About Stackbar", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(withTitle: "Settings…", action: settings, keyEquivalent: ",")
        settingsItem.target = target
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Stackbar", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Stackbar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "Stackbar", action: nil, keyEquivalent: "").submenu = appMenu

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(.separator())
        window.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = window
        NSApp.mainMenu = main
        NSApp.windowsMenu = window
    }
}
#endif
