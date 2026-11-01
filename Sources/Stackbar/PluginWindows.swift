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
    }
}
#endif
