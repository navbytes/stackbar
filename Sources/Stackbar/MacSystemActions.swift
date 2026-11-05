#if os(macOS)
import AppKit
import ApplicationServices
import StackbarHostCore
import StackbarProtocol

/// `Stackbar.system(_:)`: lock, sleep, restart and the rest, with public
/// APIs only. Restart, shut down, log out, dark mode and the Trash go through
/// System Events or Finder with `osascript`, so macOS asks the user once to
/// let Stackbar control each; nothing here blocks the main thread while that
/// question is up.
extension MacSystem {
    func perform(_ action: SystemAction) async throws {
        switch action {
        case .lockScreen:
            try await Self.lockScreen()
        case .sleep:
            try await Self.tool("/usr/bin/pmset", ["sleepnow"], doing: action)
        case .sleepDisplays:
            try await Self.tool("/usr/bin/pmset", ["displaysleepnow"], doing: action)
        case .startScreenSaver:
            try await Self.openApplication("/System/Library/CoreServices/ScreenSaverEngine.app")
        case .restart:
            try await Self.script("tell application \"System Events\" to restart", app: "System Events", doing: action)
        case .shutDown:
            try await Self.script("tell application \"System Events\" to shut down", app: "System Events", doing: action)
        case .logOut:
            try await Self.script("tell application \"System Events\" to log out", app: "System Events", doing: action)
        case .emptyTrash:
            try await Self.script("tell application \"Finder\" to if (count of items of trash) > 0 then empty trash", app: "Finder", doing: action)
        case .toggleDarkMode:
            try await Self.script("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode", app: "System Events", doing: action)
        case .hideOtherApps:
            await MainActor.run { otherApps().forEach { $0.hide() } }
        case .quitOtherApps:
            await MainActor.run { otherApps().forEach { $0.terminate() } }
        case .ejectDisks:
            try await Self.ejectDisks()
        }
    }

    /// The regular apps other than Stackbar, Finder and the app the user was
    /// in before Stackbar's palette took focus.
    @MainActor private func otherApps() -> [NSRunningApplication] {
        let kept: Set<String> = ["com.apple.finder", Bundle.main.bundleIdentifier ?? "io.navbytes.stackbar"]
        let front = previousApp
        return NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular
                && app.processIdentifier != getpid()
                && !kept.contains(app.bundleIdentifier ?? "")
                && app.processIdentifier != front?.processIdentifier
        }
    }

    /// ⌃⌘Q, the shortcut macOS locks the screen with. Posting it needs
    /// Accessibility, which pasting already asks for.
    private static func lockScreen() async throws {
        let trusted = await MainActor.run { AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) }
        guard trusted else {
            throw SystemServiceError("Stackbar needs Accessibility access to lock the screen: System Settings > Privacy & Security > Accessibility")
        }
        await MainActor.run {
            let source = CGEventSource(stateID: .combinedSessionState)
            for isDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: isDown) // kVK_ANSI_Q
                event?.flags = [.maskControl, .maskCommand]
                event?.post(tap: .cgAnnotatedSessionEventTap)
            }
        }
    }

    private static func openApplication(_ path: String) async throws {
        let opened = await MainActor.run { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        if !opened { throw SystemServiceError("could not open \(path)") }
    }

    /// Every ejectable or removable volume: USB disks, SD cards, mounted
    /// disk images.
    private static func ejectDisks() async throws {
        let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey]
        let volumes = (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []).filter { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return values?.volumeIsEjectable == true || values?.volumeIsRemovable == true
        }
        guard !volumes.isEmpty else { throw SystemServiceError("there are no disks to eject") }
        var failed: [String] = []
        for volume in volumes {
            do {
                try await MainActor.run { try NSWorkspace.shared.unmountAndEjectDevice(at: volume) }
            } catch {
                failed.append(volume.lastPathComponent)
            }
        }
        if !failed.isEmpty { throw SystemServiceError("could not eject \(failed.joined(separator: ", ")); an app may still be using it") }
    }

    private static func tool(_ path: String, _ arguments: [String], doing action: SystemAction) async throws {
        let result = try await run(RunRequest(command: path, arguments: arguments, timeout: 20))
        guard result.succeeded else {
            throw SystemServiceError("\(action.title) failed: \(result.errorText.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    private static func script(_ source: String, app: String, doing action: SystemAction) async throws {
        let result = try await run(RunRequest(command: "/usr/bin/osascript", arguments: ["-e", source], timeout: 60))
        guard result.succeeded else {
            if result.errorText.contains("-1743") {
                throw SystemServiceError("Stackbar isn't allowed to control \(app): System Settings > Privacy & Security > Automation > Stackbar > \(app)")
            }
            // The user cancelled (an app refused to quit before a restart).
            if result.errorText.contains("-128") { throw SystemServiceError("\(action.title) was cancelled") }
            throw SystemServiceError("\(action.title) failed: \(result.errorText.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    private static func run(_ request: RunRequest) async throws -> RunResult {
        let gate = CommandRunGate(root: StackbarPaths.runDirectory)
        switch await gate.run(request, id: 0, grant: .init(pluginID: "io.navbytes.stackbar.system")) {
        case .failure(let refusal): throw SystemServiceError("\(refusal)")
        case .success(let result): return result
        }
    }
}
#endif
