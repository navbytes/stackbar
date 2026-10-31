#if os(macOS)
import AppKit
import Observation
import SwiftUI
import FluidProtocol
import FluidUI

/// A plugin's menu-bar item: draws the `menuBar` tree with the shared
/// SwiftUI renderer and opens the `panel` tree in a popover.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    let controller: PluginController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let hosting: PassthroughHostingView<StatusItemContent>

    init(controller: PluginController, model: AppModel, windows: PluginWindows) {
        self.controller = controller
        hosting = PassthroughHostingView(rootView: StatusItemContent(controller: controller))
        super.init()
        statusItem.autosaveName = "fluid." + controller.source.lastPathComponent
        statusItem.behavior = .removalAllowed
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PanelView(controller: controller, model: model, windows: windows))
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            hosting.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: button.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
            button.setAccessibilityLabel(controller.name)
        }
        observe()
    }

    func remove() {
        popover.close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func showPanel() {
        guard let button = statusItem.button, !popover.isShown else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// Re-sizes the item whenever what it draws changes.
    private func observe() {
        withObservationTracking {
            _ = controller.menuBar
            _ = controller.state
            _ = controller.name
            _ = controller.isWaitingForApproval
            _ = controller.missingSecrets
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.resize()
                self?.observe()
            }
        }
        resize()
    }

    private func resize() {
        hosting.invalidateIntrinsicContentSize()
        let width = max(hosting.fittingSize.width, 22)
        statusItem.length = ceil(width)
        statusItem.button?.setAccessibilityLabel(controller.name)
    }

    @objc private func togglePanel(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPanel()
        }
    }

    func popoverDidShow(_ notification: Notification) {
        controller.setVisible(.panel, true)
    }

    func popoverDidClose(_ notification: Notification) {
        controller.setVisible(.panel, false)
    }
}

/// What the status item shows, including the host's own states (building,
/// failed, waiting for approval or a secret).
struct StatusItemContent: View {
    let controller: PluginController

    var body: some View {
        switch controller.state {
        case .failed:
            MenuBarView(node: nil, fallbackTitle: "", fallbackSymbol: "exclamationmark.triangle", fallbackRole: .critical)
        default:
            if controller.isWaitingForApproval || !controller.missingSecrets.isEmpty {
                MenuBarView(node: controller.menuBar, fallbackTitle: controller.name, fallbackSymbol: "lock.shield", fallbackRole: .warning)
                    .overlay(alignment: .topTrailing) { Circle().fill(Color.orange).frame(width: 5, height: 5) }
            } else if controller.menuBar == nil {
                MenuBarView(node: nil, fallbackTitle: "", fallbackSymbol: controller.building ? "hourglass" : "puzzlepiece.extension", fallbackRole: .secondary)
            } else {
                MenuBarView(node: controller.menuBar, fallbackTitle: controller.name)
            }
        }
    }
}

/// A hosting view that lets clicks through to the status item's button.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif
