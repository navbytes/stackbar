#if os(macOS)
import AppKit
import ApplicationServices
import StackbarHostCore
import StackbarUI
import SwiftUI

/// Marks the events the Hyper key sends, so its own listener lets them by.
private let hyperEventMarker: Int64 = 0x5374_6B48 // "StkH"

private let hyperTapCallback: CGEventTapCallBack = { _, type, event, _ in
    nonisolated(unsafe) let event = event
    let ours = MainActor.assumeIsolated { MacHyperKey.shared.handle(type, event) }
    return ours ? nil : Unmanaged.passUnretained(event)
}

/// Caps Lock as ⌃⌥⇧⌘ (`HyperKey` has the how). Runs only while the setting
/// is on and Accessibility is allowed: without the listener, Caps Lock is
/// left alone rather than turned into a key that does nothing.
@MainActor
final class MacHyperKey {
    static let shared = MacHyperKey()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var state = HyperKey.State(escapeOnTap: true)
    private var trustPoll: Timer?

    var isOn: Bool { UserDefaults.standard.bool(forKey: HyperKey.defaultsKey) }
    var listening: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// Matches the listener and the remap to the setting.
    func sync() {
        state.escapeOnTap = UserDefaults.standard.object(forKey: HyperKey.escapeDefaultsKey) as? Bool ?? true
        guard isOn else {
            stop()
            return
        }
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            pollForAccess()
            return
        }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask), callback: hyperTapCallback, userInfo: nil) else {
            HostLog.shared.write(.warning, "hyper key: could not create the keyboard listener; check Accessibility access")
            pollForAccess()
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        remap(true)
    }

    /// Puts Caps Lock back and stops listening (setting off, or quitting).
    func stop() {
        trustPoll?.invalidate()
        trustPoll = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        state.reset()
        // A remap left by a crash is cleared on the next launch too.
        remap(false)
    }

    private func pollForAccess() {
        guard trustPoll == nil else { return }
        trustPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated {
                let hyper = MacHyperKey.shared
                guard AXIsProcessTrusted() || !hyper.isOn else { return }
                hyper.trustPoll?.invalidate()
                hyper.trustPoll = nil
                hyper.sync()
            }
        }
    }

    private func remap(_ on: Bool) {
        let current = HyperKey.mappings(fromHidutil: Self.hidutil(["property", "--get", "UserKeyMapping"]) ?? "")
        let wanted = HyperKey.mappings(current, hyper: on)
        guard wanted != current else { return }
        if Self.hidutil(["property", "--set", HyperKey.hidutilJSON(wanted)]) == nil {
            HostLog.shared.write(.warning, "hyper key: hidutil could not \(on ? "remap" : "restore") Caps Lock")
        }
    }

    /// `hidutil`'s output, or nil when it failed.
    private static func hidutil(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }

    // MARK: Presses

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            state.reset()
            return false
        case .keyDown, .keyUp:
            if event.getIntegerValueField(.eventSourceUserData) == hyperEventMarker { return false }
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let time = ProcessInfo.processInfo.systemUptime
            let output = state.handle(type == .keyDown ? .keyDown(code: code, at: time) : .keyUp(code: code, at: time))
            switch output {
            case .pass:
                return false
            case .swallow:
                return true
            case .withHyper:
                guard let copy = event.copy() else { return false }
                copy.flags.formUnion([.maskCommand, .maskControl, .maskAlternate, .maskShift])
                post(copy)
                return true
            case .escape:
                let source = CGEventSource(stateID: .hidSystemState)
                for down in [true, false] {
                    if let escape = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(HyperKey.escapeKeyCode), keyDown: down) { post(escape) }
                }
                return true
            }
        default:
            return false
        }
    }

    /// Sent from the top, so global hotkeys see it like a real press.
    private func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: hyperEventMarker)
        event.post(tap: .cghidEventTap)
    }
}

/// Settings › General › Keyboard.
struct HyperKeySettings: View {
    @AppStorage(HyperKey.defaultsKey) private var on = false
    @AppStorage(HyperKey.escapeDefaultsKey) private var escape = true
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        SettingsGroup("Keyboard", footer: "Every hotkey can then use Caps Lock, such as Caps Lock-Space for the palette. Caps Lock stops locking capitals while this is on, and comes back when you turn it off or quit Stackbar.") {
            Toggle("Caps Lock is a Hyper key (⌃⌥⇧⌘)", isOn: $on)
                .toggleStyle(TrailingSwitchStyle())
                .onChange(of: on) {
                    if on, !AXIsProcessTrusted() {
                        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                    }
                    MacHyperKey.shared.sync()
                    trusted = AXIsProcessTrusted()
                }
            Toggle("Tap Caps Lock alone for Escape", isOn: $escape)
                .toggleStyle(TrailingSwitchStyle())
                .disabled(!on)
                .onChange(of: escape) { MacHyperKey.shared.sync() }
            if on, !trusted {
                Text("Waiting for Accessibility access in System Settings › Privacy & Security › Accessibility.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { trusted = AXIsProcessTrusted() }
    }
}
#endif
