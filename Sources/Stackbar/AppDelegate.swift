#if os(macOS)
import AppKit
import EventKit
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
    private var storeWindow: NSWindow?

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
        // Fires several times while macOS settles a change; plugins hear
        // once, after it has been quiet for 1.5 seconds.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.displaysChangedSoon()
            }
        }
        // Reminders (or calendars) changed, here or synced from another
        // device. Saves come in bursts; plugins hear once, a second after
        // the last.
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.remindersChangedSoon()
            }
        }
        // Apps opening and quitting come in bursts at login; plugins hear
        // once, half a second after the last.
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.appsChangedSoon()
                }
            }
        }
    }

    private var remindersDebounce: Task<Void, Never>?

    private func remindersChangedSoon() {
        remindersDebounce?.cancel()
        remindersDebounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.model.controllers.forEach { $0.remindersChanged() }
        }
    }

    private var appsDebounce: Task<Void, Never>?

    private func appsChangedSoon() {
        appsDebounce?.cancel()
        appsDebounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.model.controllers.forEach { $0.appsChanged() }
        }
    }

    private var displaysDebounce: Task<Void, Never>?

    private func displaysChangedSoon() {
        displaysDebounce?.cancel()
        displaysDebounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.model.controllers.forEach { $0.displaysChanged() }
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
        menu.addItem(item(title: "Browse the Plugin Store…", action: #selector(openStore)))
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
        let storeItem = key("Plugin Store…", #selector(openStore), "")
        storeItem.target = self
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
                storeItem,
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

    @objc private func openStore() {
        showStore()
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
    /// `stackbar://store/<plugin>` opens the plugin's page in the Store
    /// window; installing still takes the user's click there.
    private func openLink(_ url: URL) {
        if let link = StoreLink(url) {
            model.storeFocus = link.pluginID
            showStore()
            return
        }
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
        // Read before the palette or the alert below takes focus.
        let context = model.commands.captureContext(for: link.key.pluginID)
        if entry.spec.kind == .view || !entry.spec.requiredArguments.allSatisfy({ !(link.arguments[$0.name] ?? "").isEmpty }) {
            palette.open(entry, arguments: link.arguments, source: .link, context: context)
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
        Task { await model.commands.run(link.key, arguments: link.arguments, source: .link, context: context) }
    }

    /// Opens Settings on one of its pages.
    func showSettings(tab: SettingsTab) {
        model.settingsTab = tab
        showSettings()
    }

    /// Opens the Store window, on Discover or wherever it was left.
    func showStore() {
        if storeWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Plugin Store"
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            let host = NSHostingController(rootView: StoreBrowser(model: model, store: model.store))
            host.sceneBridgingOptions = [.toolbars, .title]
            window.contentViewController = host
            window.setContentSize(NSSize(width: 1040, height: 720))
            window.center()
            window.setFrameAutosaveName("StackbarStore")
            window.delegate = windows
            storeWindow = window
        }
        NSApp.activate()
        storeWindow?.makeKeyAndOrderFront(nil)
        windows.updatePresence()
    }

    /// Opens Settings, on a plugin's page when one is given.
    func showSettings(plugin: PluginController? = nil) {
        if let plugin {
            model.settingsTab = .plugin(plugin.id)
        }
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Stackbar Settings"
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            // The split view's sidebar, toolbar and page titles come from
            // SwiftUI, as they do in a Settings scene.
            let host = NSHostingController(rootView: SettingsView(model: model))
            host.sceneBridgingOptions = [.toolbars, .title]
            window.contentViewController = host
            window.setContentSize(NSSize(width: 900, height: 640))
            window.center()
            window.setFrameAutosaveName("StackbarSettings")
            window.delegate = windows
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
        windows.updatePresence()
    }
}
#endif
