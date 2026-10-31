#if os(macOS)
import AppKit
import SwiftUI
import StackbarHostCore
import StackbarProtocol

/// Full-screen alerts (`Stackbar.alert`): a dimmed, blurred cover over the
/// main screen with the plugin's buttons, above full-screen apps, until the
/// user picks a button or presses Esc.
@MainActor
final class AlertPresenter {
    static let shared = AlertPresenter()
    private var window: NSWindow?

    func show(_ note: HostNotification) {
        window?.orderOut(nil)
        guard let screen = NSScreen.main else { return }
        let window = AlertWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AlertView(note: note) { [weak self] in self?.dismiss() })
        window.setFrame(screen.frame, display: true)
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        window?.orderOut(nil)
        window = nil
    }
}

final class AlertWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { AlertPresenter.shared.dismiss() }
}

struct AlertView: View {
    let note: HostNotification
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 18) {
                Text(note.pluginName.uppercased())
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(note.title)
                    .font(.system(size: 44, weight: .bold))
                    .multilineTextAlignment(.center)
                if let body = note.body {
                    Text(body).font(.title2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                HStack(spacing: 12) {
                    ForEach(Array(note.actions.enumerated()), id: \.offset) { index, action in
                        Button(action.title) {
                            open(action)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(index == 0 ? .defaultAction : nil)
                    }
                    Button("Dismiss", action: dismiss)
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.cancelAction)
                }
                .controlSize(.extraLarge)
                .padding(.top, 8)
            }
            .padding(40)
            .frame(maxWidth: 820)
        }
    }

    private func open(_ action: NotificationAction) {
        guard let url = URL(string: action.url), let scheme = url.scheme?.lowercased(), HostServices.openableSchemes.contains(scheme) else { return }
        NSWorkspace.shared.open(url)
    }
}
#endif
