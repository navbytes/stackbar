#if os(macOS)
import AppKit
import SwiftUI
import UserNotifications
import StackbarHostCore

/// Starts the model, gives each plugin a status item, and owns the windows
/// that span plugins (palette, settings).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var shared: AppDelegate?

    let model = AppModel()
    let windows = PluginWindows()
    private(set) lazy var palette = PaletteController(model: model)
    private var items: [String: StatusItemController] = [:]
    private var emptyStateItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.mainMenu = mainMenu()
        if Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        }
        model.onPluginsChanged = { [weak self] in self?.syncItems() }
        model.start()
        _ = palette
        syncItems()

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.controllers.forEach { $0.wake() }
            }
        }
    }

    /// Clicking the Dock icon (shown while a window is open) brings the
    /// windows back, minimized ones included.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        for window in NSApp.windows where window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.arrangeInFront(nil)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Helpers exit on their own when their stdin closes with the app.
        model.prepareForTermination()
    }

    /// One status item per plugin, in plugin order; an empty-state item when
    /// there are none.
    private func syncItems() {
        let current = Set(model.controllers.map(\.id))
        for (id, item) in items where !current.contains(id) {
            item.remove()
            items[id] = nil
        }
        for controller in model.controllers where items[controller.id] == nil {
            items[controller.id] = StatusItemController(controller: controller, model: model, windows: windows)
        }
        if model.controllers.isEmpty {
            showEmptyState()
        } else if let emptyStateItem {
            NSStatusBar.system.removeStatusItem(emptyStateItem)
            self.emptyStateItem = nil
        }
    }

    private func showEmptyState() {
        guard emptyStateItem == nil else { return }
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Stackbar")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "No plugins yet", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(item(title: "Install Bundled Plugins", action: #selector(installExamples)))
        menu.addItem(item(title: "Open Plugins Folder", action: #selector(openPluginsFolder)))
        menu.addItem(item(title: "Settings…", action: #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Stackbar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        emptyStateItem = statusItem
    }

    /// Seen only while a plugin window puts Stackbar in the Dock, but its
    /// shortcuts (⌘W, ⌘C/⌘V, ⌘Q) work in every Stackbar window and panel.
    private func mainMenu() -> NSMenu {
        func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let submenu = NSMenu(title: title)
            items.forEach(submenu.addItem)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            return item
        }
        func key(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            return item
        }
        let settings = key("Settings…", #selector(openSettings), ",")
        settings.target = self
        let window = menu("Window", [
            key("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            key("Zoom", #selector(NSWindow.performZoom(_:)), ""),
            .separator(),
            key("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), ""),
        ])
        NSApp.windowsMenu = window.submenu
        let main = NSMenu()
        [
            menu("Stackbar", [
                key("About Stackbar", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
                .separator(),
                settings,
                .separator(),
                key("Hide Stackbar", #selector(NSApplication.hide(_:)), "h"),
                key("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
                .separator(),
                key("Quit Stackbar", #selector(NSApplication.terminate(_:)), "q"),
            ]),
            menu("File", [key("Close Window", #selector(NSWindow.performClose(_:)), "w")]),
            menu("Edit", [
                key("Undo", Selector(("undo:")), "z"),
                key("Redo", Selector(("redo:")), "z", [.command, .shift]),
                .separator(),
                key("Cut", #selector(NSText.cut(_:)), "x"),
                key("Copy", #selector(NSText.copy(_:)), "c"),
                key("Paste", #selector(NSText.paste(_:)), "v"),
                key("Select All", #selector(NSText.selectAll(_:)), "a"),
            ]),
            window,
        ].forEach(main.addItem)
        return main
    }

    private func item(title: String, action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    @objc private func installExamples() {
        model.installExamples()
    }

    @objc private func openPluginsFolder() {
        NSWorkspace.shared.open(StackbarPaths.pluginsDirectory)
    }

    @objc private func openSettings() {
        showSettings()
    }

    /// Opens a plugin's panel, as clicking its notification does.
    func showPanel(pluginID: String) {
        guard let controller = model.controllers.first(where: { $0.pluginID == pluginID }) else { return }
        items[controller.id]?.showPanel()
    }

    /// Opens Settings, on a plugin's page when one is given.
    func showSettings(plugin: PluginController? = nil) {
        if let plugin {
            model.settingsTab = .plugins
            model.settingsPlugin = plugin.id
        }
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Stackbar Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
            window.center()
            window.delegate = windows
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
        windows.updatePresence()
    }
}
#endif
