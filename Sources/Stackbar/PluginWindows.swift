#if os(macOS)
import AppKit
import Observation
import SwiftUI
import StackbarProtocol
import StackbarUI

/// Plugin windows: the `window` surface in a resizable window, one per plugin.
@MainActor
@Observable
final class PluginWindows: NSObject, NSWindowDelegate {
    @ObservationIgnored private var windows: [String: NSWindow] = [:]
    @ObservationIgnored private var controllers: [ObjectIdentifier: PluginController] = [:]
    /// Plugins with a window open, so the panel can say "Show Window".
    private(set) var openIDs: Set<String> = []

    func isOpen(_ controller: PluginController) -> Bool { openIDs.contains(controller.pluginID) }

    /// The plugin's open window when it isn't already in front of you:
    /// behind other windows, minimized, or in an app you've left.
    func buried(_ controller: PluginController) -> NSWindow? {
        guard let window = windows[controller.pluginID] else { return nil }
        if window.isMiniaturized || !window.isVisible { return window }
        return NSApp.isActive && window.isKeyWindow ? nil : window
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
        openIDs.insert(controller.pluginID)
        controller.setVisible(.window, true)
        show(window)
    }

    func show(_ window: NSWindow) {
        DockPresence.shared.track(window)
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close(_ pluginID: String) {
        windows[pluginID]?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let controller = controllers.removeValue(forKey: ObjectIdentifier(window)) else { return }
        controller.setVisible(.window, false)
        windows[controller.pluginID] = nil
        openIDs.remove(controller.pluginID)
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
