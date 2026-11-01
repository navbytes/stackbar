#if os(macOS)
import AppKit
import SwiftUI
import UserNotifications
import StackbarHostCore
import StackbarProtocol

/// Starts the model, gives each plugin a status item, and owns the windows
/// that span plugins (palette, settings).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static private(set) weak var shared: AppDelegate?

    let model = AppModel()
    let windows = PluginWindows()
    private(set) lazy var palette = PaletteController(model: model)
    private var items: [String: StatusItemController] = [:]
    private var headless: [String: HeadlessPanelController] = [:]
    private var emptyStateItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
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

    func applicationWillTerminate(_ notification: Notification) {
        // Helpers exit on their own when their stdin closes with the app.
        model.prepareForTermination()
    }

    /// One status item per plugin that draws in the menu bar, in plugin
    /// order; a centered panel for the others that have a panel; an
    /// empty-state item when there are no plugins.
    private func syncItems() {
        let inMenuBar = Set(model.controllers.filter(\.showsInMenuBar).map(\.id))
        let withPanel = Set(model.controllers.filter(\.hasHeadlessPanel).map(\.id))
        for (id, item) in items where !inMenuBar.contains(id) {
            item.remove()
            items[id] = nil
        }
        for (id, panel) in headless where !withPanel.contains(id) {
            panel.remove()
            headless[id] = nil
        }
        for controller in model.controllers {
            if inMenuBar.contains(controller.id), items[controller.id] == nil {
                items[controller.id] = StatusItemController(controller: controller, model: model, windows: windows)
            }
            if withPanel.contains(controller.id), headless[controller.id] == nil {
                headless[controller.id] = HeadlessPanelController(controller: controller, model: model, windows: windows)
            }
        }
        model.headlessPanelsChanged(model.controllers.filter(\.hasHeadlessPanel))
        // Stackbar keeps one item of its own while no plugin draws there, so
        // Settings and the palette are always reachable.
        if inMenuBar.isEmpty {
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
        menu.delegate = self
        menu.addItem(item(title: "Command Palette  ⌃⌥Space", action: #selector(openPalette)))
        menu.addItem(.separator())
        menu.addItem(item(title: "Install Bundled Plugins", action: #selector(installExamples)))
        menu.addItem(item(title: "Open Plugins Folder", action: #selector(openPluginsFolder)))
        menu.addItem(item(title: "Settings…", action: #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Stackbar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        emptyStateItem = statusItem
    }

    /// "No plugins yet" leads the empty-state menu only while that's true.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let note = menu.items.first { $0.tag == 7 }
        if model.controllers.isEmpty, note == nil {
            let item = NSMenuItem(title: "No plugins yet", action: nil, keyEquivalent: "")
            item.tag = 7
            menu.insertItem(item, at: 0)
        } else if !model.controllers.isEmpty, let note {
            menu.removeItem(note)
        }
    }

    private func item(title: String, action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    @objc private func openPalette() {
        palette.toggle()
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
        if let item = items[controller.id] {
            item.showPanel()
        } else {
            headless[controller.id]?.show()
        }
    }

    /// Settings → Commands, on one command.
    func showCommandSettings(_ key: CommandKey? = nil) {
        model.settingsTab = .commands
        model.settingsCommand = key
        showSettings()
    }

    // MARK: - Links

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { openLink(url) }
    }

    /// `stackbar://commands/<plugin>/<command>?name=value`. A view opens in
    /// the palette, where the user sees it before anything happens. A run
    /// command runs only once the user allowed links to run it.
    private func openLink(_ url: URL) {
        guard let link = CommandLink(url.absoluteString) else {
            HUD.shared.show("Stackbar doesn't know the link \(url.absoluteString)", isError: true)
            return
        }
        guard let entry = model.commands.registry.entry(link.key) else {
            HUD.shared.show("\(link.key) is not an installed command", isError: true)
            return
        }
        guard entry.spec.exposure == .everywhere else {
            HUD.shared.show("\(entry.spec.title) can only be run from inside Stackbar", isError: true)
            return
        }
        if entry.spec.kind == .view || !entry.spec.requiredArguments.allSatisfy({ !(link.arguments[$0.name] ?? "").isEmpty }) {
            palette.open(entry, arguments: link.arguments, source: .link)
            return
        }
        var preference = model.commands.preferences[link.key]
        if !preference.linksAllowed {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Allow links to run \(entry.spec.title)?"
            let details = link.arguments.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
            alert.informativeText = "A link asks to run \(entry.spec.title) from \(entry.pluginName)." + (details.isEmpty ? "" : "\n\n" + details) + "\n\nYou can change this later in Settings → Commands."
            alert.addButton(withTitle: "Run Once")
            alert.addButton(withTitle: "Always Allow")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                break
            case .alertSecondButtonReturn:
                preference.linksAllowed = true
                try? model.commands.set(preference, for: link.key)
            default:
                return
            }
        }
        Task { await model.commands.run(link.key, arguments: link.arguments, source: .link) }
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
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
#endif
