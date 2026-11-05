#if os(macOS)
import AppKit
import ApplicationServices
import StackbarHostCore
import StackbarProtocol

extension MacSystem {
    func setExpansions(_ expansions: [TextExpansion], pluginID: String, pluginName: String) throws -> ExpansionStatus {
        try MacTextExpansion.registry.set(expansions, pluginID: pluginID, pluginName: pluginName)
        return Self.onMainActor { MacTextExpansion.shared.sync(prompting: !expansions.isEmpty); return MacTextExpansion.shared.status(for: pluginID) }
    }

    func expansionStatus(pluginID: String) -> ExpansionStatus {
        Self.onMainActor { MacTextExpansion.shared.status(for: pluginID) }
    }

    fileprivate static func onMainActor<T: Sendable>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(body) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
    }
}

/// The tap's callback, on the main run loop. It only watches: every event
/// goes on to the app.
private let expansionTapCallback: CGEventTapCallBack = { _, type, event, _ in
    nonisolated(unsafe) let event = event
    MainActor.assumeIsolated { MacTextExpansion.shared.handle(type, event) }
    return Unmanaged.passUnretained(event)
}

/// Watches typing for the keywords plugins registered, and expands one when
/// it is typed: deletes it with backspaces and runs the plugin's command
/// (which pastes). Plugins never see keystrokes: the matching happens here,
/// on at most the last 33 characters, which are dropped on every click,
/// arrow key, shortcut and app switch. Nothing typed is stored or logged.
///
/// The keyboard listener exists only while some plugin has keywords and the
/// user hasn't switched expansion off. Secure Input (password fields)
/// blocks it, as it blocks every listener, and the apps in the excluded
/// list are skipped.
@MainActor
final class MacTextExpansion {
    static let shared = MacTextExpansion()
    nonisolated static let registry = TextExpansionRegistry()

    /// The user's switch (Settings › Privacy & Secrets).
    static let enabledKey = "textExpansion"
    /// Bundle ids where keywords never expand.
    static let excludedKey = "textExpansionExcludedApps"
    /// Password managers, where a stray expansion would land in a vault.
    static let defaultExcluded = ["com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "com.apple.Passwords", "com.apple.keychainaccess"]
    /// Marks the backspaces we post, so the tap doesn't count them.
    private static let ownEventMark: Int64 = 0x5354_4b42 // "STKB"

    /// Runs the plugin's command for a typed keyword (wired to `CommandCenter`).
    var onExpand: ((CommandKey) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var trustPoll: Timer?
    private var promptedForAccess = false
    private var matcher = TextExpansionMatcher()
    private var excludedFront = false
    private var observers: [NSObjectProtocol] = []

    private init() {
        UserDefaults.standard.register(defaults: [Self.enabledKey: true, Self.excludedKey: Self.defaultExcluded])
        Self.registry.onChange = { live in
            Task { @MainActor in MacTextExpansion.shared.matcher.update(live) }
        }
    }

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            shared.sync(prompting: newValue)
        }
    }

    static var excludedApps: [String] {
        get { UserDefaults.standard.stringArray(forKey: excludedKey) ?? defaultExcluded }
        set {
            UserDefaults.standard.set(newValue, forKey: excludedKey)
            shared.frontChanged(NSWorkspace.shared.frontmostApplication)
        }
    }

    // MARK: Registration

    /// Creates the listener when keywords exist and expansion is on, and
    /// removes it otherwise.
    func sync(prompting: Bool) {
        matcher.update(Self.registry.live)
        guard !Self.registry.isEmpty, Self.isEnabled else {
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

    func status(for pluginID: String) -> ExpansionStatus {
        let count = Self.registry.count(for: pluginID)
        guard count > 0 else { return .off }
        let enabled = Self.isEnabled
        let trusted = AXIsProcessTrusted()
        let secure = MacKeyLayer.secureInputHolder()
        let live = tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
        return ExpansionStatus(listening: enabled && live && trusted && secure == nil, keywords: count, turnedOff: !enabled,
                               needsAccessibility: !trusted, secureInputApp: secure, taken: Self.registry.taken(for: pluginID))
    }

    /// For Settings: how many keywords are live, from how many plugins.
    var summary: (keywords: Int, plugins: [String], listening: Bool, needsAccessibility: Bool) {
        let live = Self.registry.live
        let names = live.reduce(into: [String]()) { if !$0.contains($1.pluginName) { $0.append($1.pluginName) } }
        let listening = tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
        return (live.count, names, listening, !AXIsProcessTrusted())
    }

    private func pollForAccess() {
        guard trustPoll == nil else { return }
        trustPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated {
                let expansion = MacTextExpansion.shared
                guard AXIsProcessTrusted() || Self.registry.isEmpty || !Self.isEnabled else { return }
                expansion.trustPoll?.invalidate()
                expansion.trustPoll = nil
                expansion.sync(prompting: false)
            }
        }
    }

    private func createTap() {
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly, eventsOfInterest: mask, callback: expansionTapCallback, userInfo: nil) else {
            HostLog.shared.write(.warning, "text expansion: could not create the keyboard listener; check Accessibility access")
            pollForAccess()
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        frontChanged(NSWorkspace.shared.frontmostApplication)
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { MacTextExpansion.shared.frontChanged(app) }
        })
    }

    private func removeTap() {
        trustPoll?.invalidate()
        trustPoll = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        matcher.reset()
    }

    private func frontChanged(_ app: NSRunningApplication?) {
        matcher.reset()
        let id = app?.bundleIdentifier ?? ""
        // Never in Stackbar's own windows (the palette, Settings), where a
        // keyword is being typed into a snippet, not used.
        excludedFront = app?.processIdentifier == getpid() || Self.excludedApps.contains(id)
    }

    // MARK: Typing

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            matcher.reset()
        case .keyDown:
            guard event.getIntegerValueField(.eventSourceUserData) != Self.ownEventMark else { return }
            guard !excludedFront, !matcher.isEmpty else { return }
            typed(event)
        default:
            // A click moves the caret somewhere we can't see.
            matcher.reset()
        }
    }

    private func typed(_ event: CGEvent) {
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            matcher.reset()
            return
        }
        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case 51: // Delete
            matcher.deleteBackward()
            return
        case 36, 76, 48, 53, 117, 115, 119, 116, 121, 123, 124, 125, 126: // Return, Enter, Tab, Esc, ⌦, Home, End, Page Up/Down, arrows
            matcher.reset()
            return
        default:
            break
        }
        guard let text = NSEvent(cgEvent: event)?.characters, !text.isEmpty,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return }
        guard let match = matcher.type(text) else { return }
        expand(match)
    }

    /// The keyword's last character is still on its way to the app: let it
    /// land, delete the keyword, then run the command.
    private func expand(_ match: TextExpansionMatcher.Match) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            let source = CGEventSource(stateID: .combinedSessionState)
            for _ in 0..<match.deleteCount {
                for isDown in [true, false] {
                    let event = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: isDown)
                    event?.flags = []
                    event?.setIntegerValueField(.eventSourceUserData, value: Self.ownEventMark)
                    event?.post(tap: .cgAnnotatedSessionEventTap)
                }
            }
            try? await Task.sleep(for: .milliseconds(20))
            onExpand?(CommandKey(pluginID: match.pluginID, commandID: match.command))
        }
    }
}
#endif
