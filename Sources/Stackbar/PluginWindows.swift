#if os(macOS)
import AppKit
import Observation
import SwiftUI
import StackbarProtocol
import StackbarUI

/// Plugin windows: the `window` surface in a resizable window, one per plugin.
/// While one (or Settings) is open Stackbar shows in the Dock and ⌘Tab, so a
/// window behind others can be found again; menu-bar only after the last.
@MainActor
@Observable
final class PluginWindows: NSObject, NSWindowDelegate {
    static let dockIconKey = "dockIconWithWindows"

    private var windows: [String: NSWindow] = [:]
    @ObservationIgnored private var controllers: [ObjectIdentifier: PluginController] = [:]

    func isOpen(_ pluginID: String) -> Bool {
        windows[pluginID] != nil
    }

    /// Counts every titled window, so Settings too; panels (the palette) don't.
    func updatePresence(excluding closing: NSWindow? = nil) {
        let open = NSApp.windows.contains { $0 !== closing && !($0 is NSPanel) && $0.styleMask.contains(.titled) && ($0.isVisible || $0.isMiniaturized) }
        let dock = open && (UserDefaults.standard.object(forKey: Self.dockIconKey) as? Bool ?? true)
        NSApp.setActivationPolicy(dock ? .regular : .accessory)
    }

    /// The plugin's open window when it isn't already in front of you:
    /// behind other windows, minimized, or in an app you've left.
    func buried(_ controller: PluginController) -> NSWindow? {
        guard let window = windows[controller.pluginID] else { return nil }
        if window.isMiniaturized || !window.isVisible { return window }
        return NSApp.isActive && window.isKeyWindow ? nil : window
    }

    func show(_ window: NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func open(_ controller: PluginController) {
        if let window = windows[controller.pluginID] {
            show(window)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = controller.name
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: PluginWindowView(controller: controller))
        window.setFrameAutosaveName("stackbar.window." + controller.pluginID)
        window.delegate = self
        window.center()
        window.addTitlebarAccessoryViewController(PinAccessory(window: window, pluginID: controller.pluginID))
        windows[controller.pluginID] = window
        controllers[ObjectIdentifier(window)] = controller
        controller.setVisible(.window, true)
        window.makeKeyAndOrderFront(nil)
        updatePresence()
        NSApp.activate()
    }

    func close(_ pluginID: String) {
        windows[pluginID]?.close()
    }

    /// Also the Settings window's delegate, so closing it updates the Dock.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if let controller = controllers.removeValue(forKey: ObjectIdentifier(window)) {
            controller.setVisible(.window, false)
            windows[controller.pluginID] = nil
        }
        updatePresence(excluding: window)
    }
}

struct PluginWindowView: View {
    let controller: PluginController

    var body: some View {
        ScrollView {
            Group {
                if let node = controller.window ?? controller.panel {
                    NodeView(node: node, send: controller.send)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(16)
        }
        .frame(minWidth: 360, minHeight: 240)
        .environment(\.stackbarImageData, AppModel.previewImages(for: controller))
        .environment(\.stackbarRemoteImage, controller.remoteImages)
    }
}
/// The title bar's "Keep on top" pin: a pinned window floats above other
/// apps' windows (not over full-screen apps), for things you glance at while
/// working, like the day's meetings during a call. Remembered per plugin; a
/// plugin can't set it, only you.
final class PinAccessory: NSTitlebarAccessoryViewController {
    private let pluginID: String
    private weak var target: NSWindow?
    private let button = NSButton()

    private var key: String { "stackbar.pinned." + pluginID }
    private var pinned: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    init(window: NSWindow, pluginID: String) {
        self.pluginID = pluginID
        target = window
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .trailing
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.target = self
        button.action = #selector(toggle)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 30, height: 22))
        button.frame = container.bounds.insetBy(dx: 4, dy: 1)
        button.autoresizingMask = [.width, .height]
        container.addSubview(button)
        view = container
        apply()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func toggle() {
        pinned.toggle()
        apply()
    }

    private func apply() {
        target?.level = pinned ? .floating : .normal
        let title = pinned ? "Unpin: stop keeping on top" : "Keep on top of other windows"
        button.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: title)
        button.contentTintColor = pinned ? .controlAccentColor : .secondaryLabelColor
        button.toolTip = title
        button.setAccessibilityLabel(title)
    }
}
#endif
