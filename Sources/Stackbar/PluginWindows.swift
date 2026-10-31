#if os(macOS)
import AppKit
import SwiftUI
import StackbarProtocol
import StackbarUI

/// Plugin windows: the `window` surface in a resizable window, one per plugin.
@MainActor
final class PluginWindows: NSObject, NSWindowDelegate {
    private var windows: [String: NSWindow] = [:]
    private var controllers: [ObjectIdentifier: PluginController] = [:]

    func open(_ controller: PluginController) {
        if let window = windows[controller.pluginID] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
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
        NSApp.activate()
    }

    func close(_ pluginID: String) {
        windows[pluginID]?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let controller = controllers.removeValue(forKey: ObjectIdentifier(window)) else { return }
        controller.setVisible(.window, false)
        windows[controller.pluginID] = nil
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
    }
}
#endif
