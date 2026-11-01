#if os(macOS)
import AppKit
import SwiftUI
import StackbarHostCore
import StackbarProtocol

/// The panel of a plugin with no menu-bar item (it lists no `.menuBar`, or
/// the user hid it): a centered floating panel like the palette's, opened by
/// the plugin's hotkey or "Open <Plugin>" in the palette.
@MainActor
final class HeadlessPanelController: NSObject, NSWindowDelegate {
    let controller: PluginController
    private let model: AppModel
    private let windows: PluginWindows
    private var panel: KeyablePanel?
    private var hotKey: HotKey?
    private var hotKeySpec: String?

    init(controller: PluginController, model: AppModel, windows: PluginWindows) {
        self.controller = controller
        self.model = model
        self.windows = windows
        super.init()
        observe()
    }

    func remove() {
        hotKey?.unregister()
        hotKey = nil
        hide()
    }

    var isShown: Bool { panel?.isVisible == true }

    func toggle() {
        if isShown { hide() } else { show() }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.center()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        controller.setVisible(.panel, true)
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        controller.setVisible(.panel, false)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func makePanel() -> KeyablePanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 480),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let hosting = NSHostingController(rootView: PanelView(controller: controller, model: model, windows: windows).frame(width: 380))
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
        panel.delegate = self
        panel.onClose = { [weak self] in self?.hide() }
        return panel
    }

    /// Follows the manifest's `hotkey`.
    private func observe() {
        withObservationTracking {
            _ = controller.manifest
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        let spec = controller.manifest?.hotkey
        guard spec != hotKeySpec else { return }
        hotKeySpec = spec
        hotKey?.unregister()
        hotKey = spec.flatMap(HotKeySpec.init).flatMap { parsed in
            HotKey(spec: parsed) { [weak self] in self?.toggle() }
        }
    }
}
#endif
