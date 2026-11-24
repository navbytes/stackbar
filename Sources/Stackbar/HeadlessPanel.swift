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
    /// The content's own height at the panel's width, asked of SwiftUI.
    private var idealSize: (() -> CGSize)?
    private var fitPending = false
    private static let width: CGFloat = 380
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
        fit()
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

    /// Sizes the panel to its content on the next turn of the run loop,
    /// once, however many changes came in meanwhile: never from inside a
    /// layout pass.
    private func scheduleFit() {
        guard !fitPending else { return }
        fitPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            fitPending = false
            fit()
        }
    }

    /// The panel's content height (the scroll view stops growing at its own
    /// cap), keeping the top edge where it is so the panel grows downward.
    private func fit() {
        guard let panel, let ideal = idealSize?() else { return }
        let maxHeight = (panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        let height = min(max(ideal.height, panel.contentMinSize.height), maxHeight).rounded()
        let current = panel.contentRect(forFrameRect: panel.frame)
        guard abs(current.height - height) >= 1 else { return }
        let frame = panel.frameRect(forContentRect: NSRect(x: current.minX, y: current.maxY - height, width: Self.width, height: height))
        panel.setFrame(frame, display: true)
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
        let view = PanelView(controller: controller, model: model, windows: windows) { [weak self] _ in
            self?.scheduleFit()
        }
        let hosting = NSHostingController(rootView: view.frame(width: Self.width))
        // Not `.preferredContentSize`: that lets SwiftUI move this titled
        // window's frame from inside AppKit's layout pass, and wrapping text
        // in the scroll view (a Dictionary definition) kept changing the
        // asked-for size each pass until AppKit threw and Stackbar quit
        // (0.42.1). The panel sizes itself to its content after layout
        // instead, in `fit()`, as the other windows do since 0.42.2.
        panel.hostSwiftUI(hosting, minSize: NSSize(width: Self.width, height: 120))
        idealSize = { [weak hosting] in hosting?.sizeThatFits(in: CGSize(width: Self.width, height: .greatestFiniteMagnitude)) ?? .zero }
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
        let spec = CommandHotKeys.opensPanel(controller.manifest) ? controller.manifest?.hotkey : nil
        guard spec != hotKeySpec else { return }
        hotKeySpec = spec
        hotKey?.unregister()
        hotKey = spec.flatMap(HotKeySpec.init).flatMap { parsed in
            HotKey(spec: parsed) { [weak self] in self?.toggle() }
        }
    }
}
#endif
