#if os(macOS)
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import StackbarHostCore
import StackbarProtocol
import SwiftUI

extension MacSystem {
    func runningApps() async throws -> [RunningApp] {
        await MainActor.run { MacKeyLayer.running() }
    }

    func activateApp(_ id: String, launch: Bool) async throws {
        let outcome = await MainActor.run { MacKeyLayer.shared.perform(launch ? .launchIfNeeded(id) : .activate(id)) }
        if let outcome { throw SystemServiceError(outcome) }
    }

    func hideApp(_ id: String) async throws {
        let outcome = await MainActor.run { MacKeyLayer.shared.perform(.hide(id)) }
        if let outcome { throw SystemServiceError(outcome) }
    }

    func setKeyLayer(_ layer: KeyLayer?, pluginID: String, pluginName: String) throws -> KeyLayerStatus {
        try MacKeyLayer.registry.set(layer, pluginID: pluginID, pluginName: pluginName)
        return Self.onMainThread { MacKeyLayer.shared.sync(prompting: layer != nil); return MacKeyLayer.shared.status(for: pluginID) }
    }

    func keyLayerStatus(pluginID: String) -> KeyLayerStatus {
        Self.onMainThread { MacKeyLayer.shared.status(for: pluginID) }
    }

    fileprivate static func onMainThread<T: Sendable>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(body) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
    }
}

/// The tap's callback. The tap's run-loop source is on the main run loop, so
/// it is called on the main thread.
private let keyLayerTapCallback: CGEventTapCallBack = { _, type, event, _ in
    nonisolated(unsafe) let event = event
    let ours = MainActor.assumeIsolated { MacKeyLayer.shared.handle(type, event) }
    return ours ? nil : Unmanaged.passUnretained(event)
}

/// The key layers' one keyboard listener: a session event tap that, while a
/// layer's trigger (Right ⌘) is held, routes each key with `KeyLayerRouter`
/// and switches apps right inside the press. The spike (PR #73) found that a
/// plain `activate()` from here lands every time; `openApplication` is kept
/// as the fallback. The tap exists only while some plugin has a layer.
@MainActor
final class MacKeyLayer {
    static let shared = MacKeyLayer()
    /// Thread-safe: `HostServices` registers layers from any thread.
    nonisolated static let registry = KeyLayerRegistry()

    /// Runs a plugin's assign command (wired to `CommandCenter`).
    var onAssign: ((CommandKey, [String: String]) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var trustPoll: Timer?
    private var promptedForAccess = false
    /// The listener couldn't be made: said once in the log, not on every retry.
    private var reportedTapFailure = false
    private var held: Set<KeyLayerTrigger> = []
    /// Key codes whose key-down was ours, so their key-up is ours too.
    private var swallowed: Set<Int64> = []
    private var overlayTask: Task<Void, Never>?
    private let overlay = KeyLayerOverlay()

    // MARK: Registration

    /// Creates the tap when a layer exists and removes it when none does.
    func sync(prompting: Bool) {
        if Self.registry.isEmpty {
            removeTap()
            return
        }
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            if prompting, !promptedForAccess {
                promptedForAccess = true
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            }
            pollForAccess()
            return
        }
        createTap()
    }

    func status(for pluginID: String) -> KeyLayerStatus {
        guard Self.registry.registration(for: pluginID) != nil else { return .off }
        let conflict = Self.registry.conflict(for: pluginID)
        let trusted = AXIsProcessTrusted()
        let secure = Self.secureInputHolder()
        let live = tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
        return KeyLayerStatus(listening: live && trusted && conflict == nil && secure == nil, needsAccessibility: !trusted, secureInputApp: secure, conflict: conflict)
    }

    private func pollForAccess() {
        guard trustPoll == nil else { return }
        trustPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated {
                let layer = MacKeyLayer.shared
                guard AXIsProcessTrusted() || Self.registry.isEmpty else { return }
                layer.trustPoll?.invalidate()
                layer.trustPoll = nil
                layer.sync(prompting: false)
            }
        }
    }

    private func createTap() {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: keyLayerTapCallback, userInfo: nil) else {
            if !reportedTapFailure {
                reportedTapFailure = true
                HostLog.shared.write(.warning, "key layer: could not create the keyboard listener; check Accessibility access")
            }
            pollForAccess()
            return
        }
        reportedTapFailure = false
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    private func removeTap() {
        trustPoll?.invalidate()
        trustPoll = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        held = []
        swallowed = []
        hideOverlay()
    }

    // MARK: Presses

    /// Whether the event is ours (and so goes no further). Runs inside the
    /// tap: keep it quick, or macOS switches the tap off.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            HostLog.shared.write(.warning, "key layer: macOS paused the keyboard listener; turning it back on")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // Presses and releases in the gap never reached us: start from
            // the modifiers held now, and forget swallowed keys.
            held = Self.rightModifiers(CGEventSource.flagsState(.combinedSessionState))
            swallowed = []
            hideOverlay()
            return false
        case .flagsChanged:
            held = Self.rightModifiers(event.flags)
            overlayHeldChanged()
            return false
        case .keyDown:
            hideOverlay()
            guard !held.isEmpty,
                  let key = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else { return false }
            let decision = KeyLayerRouter.route(key: key, held: held, layers: Self.registry.listening, running: Self.running())
            guard decision != .passThrough else { return false }
            swallowed.insert(event.getIntegerValueField(.keyboardEventKeycode))
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { apply(decision) }
            return true
        case .keyUp:
            return swallowed.remove(event.getIntegerValueField(.keyboardEventKeycode)) != nil
        default:
            return false
        }
    }

    private func apply(_ decision: KeyLayerRouter.Decision) {
        switch decision {
        case .activate(let id): _ = perform(.activate(id))
        case .launch(let id): _ = perform(.launchIfNeeded(id))
        case .hide(let id): _ = perform(.hide(id))
        case .cycleWindows(let id): _ = perform(.cycleWindows(id))
        case .assign(let pluginID, let command, let key, let app):
            onAssign?(CommandKey(pluginID: pluginID, commandID: command), ["key": key, "app": app])
        case .passThrough, .swallow:
            break
        }
    }

    enum Action {
        case activate(String), launchIfNeeded(String), hide(String), cycleWindows(String)
    }

    /// Does it; a failure in words, or nil.
    @discardableResult
    func perform(_ action: Action) -> String? {
        switch action {
        case .activate(let id), .launchIfNeeded(let id):
            guard let app = Self.app(id) else {
                guard case .launchIfNeeded = action else { return "\(id) isn't running" }
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return "no app \(id) is installed" }
                Self.open(url)
                return nil
            }
            if app.isHidden { app.unhide() }
            app.activate()
            // Activation is a request macOS may turn down; opening the app
            // again is what a Dock click does, and lands when it doesn't.
            let pid = app.processIdentifier
            let url = app.bundleURL
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier != pid, let url else { return }
                Self.open(url)
            }
            return nil
        case .hide(let id):
            guard let app = Self.app(id) else { return "\(id) isn't running" }
            app.hide()
            return nil
        case .cycleWindows(let id):
            guard let app = Self.app(id) else { return "\(id) isn't running" }
            // This runs inside the keyboard tap: the messages to the app go
            // to the worker, so a slow app can't stall typing everywhere.
            let pid = app.processIdentifier
            AXWorker.send {
                guard MacKeyLayer.raiseBackmostWindow(of: pid) else { return }
                Task { @MainActor in NSRunningApplication(processIdentifier: pid)?.activate() }
            }
            return nil
        }
    }

    // MARK: Overlay

    private func overlayHeldChanged() {
        overlayTask?.cancel()
        guard held.count == 1, let registration = Self.registry.listening.first(where: { held.contains($0.layer.trigger) }), registration.layer.overlay else {
            hideOverlay()
            return
        }
        overlayTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, self.held == [registration.layer.trigger] else { return }
            self.overlay.show(registration.layer, running: Self.running())
        }
    }

    private func hideOverlay() {
        overlayTask?.cancel()
        overlayTask = nil
        overlay.hide()
    }

    // MARK: Helpers

    static func running() -> [RunningApp] {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.bundleIdentifier != nil }
            .map { RunningApp(id: $0.bundleIdentifier!, name: $0.localizedName ?? $0.bundleIdentifier!, path: $0.bundleURL?.path, isActive: $0.processIdentifier == front, isHidden: $0.isHidden) }
    }

    private static func app(_ id: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: id).first { !$0.isTerminated }
    }

    private static func open(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }

    /// The right-hand modifiers held, from the device-dependent flag bits.
    static func rightModifiers(_ flags: CGEventFlags) -> Set<KeyLayerTrigger> {
        // NX_DEVICERCMDKEYMASK and friends, from IOLLEvent.h.
        let raw = flags.rawValue
        var held: Set<KeyLayerTrigger> = []
        if flags.contains(.maskCommand), raw & 0x10 != 0 { held.insert(.rightCommand) }
        if flags.contains(.maskAlternate), raw & 0x40 != 0 { held.insert(.rightOption) }
        if flags.contains(.maskControl), raw & 0x2000 != 0 { held.insert(.rightControl) }
        if flags.contains(.maskShift), raw & 0x04 != 0 { held.insert(.rightShift) }
        return held
    }

    /// The app holding Secure Input, which blocks every key listener.
    static func secureInputHolder() -> String? {
        guard IsSecureEventInputEnabled() else { return nil }
        let session = CGSessionCopyCurrentDictionary() as NSDictionary?
        if let pid = (session?["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value,
           let name = NSRunningApplication(processIdentifier: pid)?.localizedName {
            return name
        }
        return "an app"
    }

    /// Raises the app's backmost standard window; false when it has fewer
    /// than two. Runs on `AXWorker`; the caller then brings the app forward.
    private nonisolated static func raiseBackmostWindow(of pid: pid_t) -> Bool {
        let element = AXWorker.timed(AXUIElementCreateApplication(pid))
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return false }
        let standard = windows.filter { window in
            AXWorker.timed(window)
            var subrole: CFTypeRef?
            var minimized: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
            return (subrole as? String) == kAXStandardWindowSubrole as String && (minimized as? Bool) != true
        }
        guard standard.count > 1, let back = standard.last else { return false }
        AXUIElementPerformAction(back, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(back, kAXMainAttribute as CFString, kCFBooleanTrue)
        return true
    }
}

/// The letter map shown while a layer's trigger is held on its own.
@MainActor
final class KeyLayerOverlay {
    private var panel: NSPanel?

    func show(_ layer: KeyLayer, running: [RunningApp]) {
        let entries = Self.entries(layer, running: running)
        guard !entries.isEmpty else { return }
        let panel = self.panel ?? make()
        self.panel = panel
        let view = NSHostingView(rootView: KeyLayerOverlayView(trigger: layer.trigger, entries: entries))
        panel.contentView = view
        let size = view.fittingSize
        let screen = (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrame(NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    struct Entry: Identifiable {
        var id: String { key }
        var key: String
        var name: String
        var icon: NSImage?
        var isRunning: Bool
        var isFront: Bool
    }

    /// One entry per key: its first running app, or its first app.
    static func entries(_ layer: KeyLayer, running: [RunningApp]) -> [Entry] {
        layer.bindings.sorted { $0.key < $1.key }.compactMap { binding in
            let live = binding.apps.compactMap { id in running.first { $0.id == id } }
            if let app = live.first(where: \.isActive) ?? live.first {
                return Entry(key: binding.key, name: app.name, icon: app.path.map { NSWorkspace.shared.icon(forFile: $0) }, isRunning: true, isFront: app.isActive)
            }
            guard binding.launch, let id = binding.apps.first, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            return Entry(key: binding.key, name: url.deletingPathExtension().lastPathComponent, icon: NSWorkspace.shared.icon(forFile: url.path), isRunning: false, isFront: false)
        }
    }

    private func make() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }
}

private struct KeyLayerOverlayView: View {
    var trigger: KeyLayerTrigger
    var entries: [KeyLayerOverlay.Entry]

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hold \(trigger.title) and press")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(entries) { entry in
                    HStack(spacing: 8) {
                        Text(entry.key.uppercased())
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 5).fill(entry.isFront ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.1)))
                        if let icon = entry.icon {
                            Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                        }
                        Text(entry.name)
                            .font(.system(size: 13, weight: entry.isRunning ? .semibold : .regular))
                            .foregroundStyle(entry.isRunning ? .primary : .secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: CGFloat(min(4, entries.count)) * 172 + 32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
#endif
