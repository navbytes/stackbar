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
        if Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        }
        DockPresence.installMainMenu(settings: #selector(openSettings), target: self)
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
            settingsWindow = window
        }
        if let settingsWindow { DockPresence.shared.track(settingsWindow) }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
#endif
