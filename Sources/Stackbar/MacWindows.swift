#if os(macOS)
import AppKit
import ApplicationServices
import StackbarHostCore
import StackbarProtocol

extension MacSystem {
    func windows() async throws -> WindowSnapshot {
        guard await MainActor.run(body: { MacWindows.isTrusted() }) else { throw MacWindows.untrusted }
        return await MainActor.run { MacWindows.live().snapshot }
    }

    func arrangeWindows(_ placements: [WindowPlacement], launch: Bool) async throws -> ArrangeResult {
        guard await MainActor.run(body: { MacWindows.isTrusted() }) else { throw MacWindows.untrusted }
        let opened = launch ? await MacWindows.launchMissing(placements) : []
        var result = await MainActor.run { MacWindows.arrange(placements) }
        result.opened = opened
        return result
    }
}

/// Windows through Accessibility: reading every regular app's standard
/// windows, and moving them. Core Graphics' window list gives the order front
/// to back (its bounds need no Screen Recording access; titles would).
/// Windows on other Spaces and in full screen are not listed by most apps,
/// so a layout covers the current Space.
@MainActor
enum MacWindows {
    nonisolated static let untrusted = SystemServiceError("Stackbar needs Accessibility access to see and move windows: System Settings > Privacy & Security > Accessibility")

    /// What is on screen, with each window's Accessibility element and the
    /// process it belongs to, in the same order as `snapshot.windows`.
    struct Live {
        var snapshot: WindowSnapshot
        var elements: [AXUIElement]
        var pids: [pid_t]
    }

    static func isTrusted() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    // MARK: Reading

    static func live() -> Live {
        let displays = displays()
        let base = WindowSnapshot(displays: displays)
        let stack = onScreenStack()
        var entries: [(info: WindowInfo, element: AXUIElement, pid: pid_t)] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isTerminated && app.processIdentifier != getpid() {
            guard let bundleID = app.bundleIdentifier else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.25)
            for window in elements(element, kAXWindowsAttribute) {
                if let subrole = string(window, kAXSubroleAttribute), subrole != kAXStandardWindowSubrole { continue }
                if bool(window, "AXFullScreen") { continue }
                guard let frame = frame(window), frame.width > 1, frame.height > 1 else { continue }
                let minimized = bool(window, kAXMinimizedAttribute)
                let onScreen = stack.firstIndex(where: { $0.pid == app.processIdentifier && close($0.frame, frame) })
                let rank = minimized ? Int.max : (onScreen ?? Int.max - 1)
                let info = WindowInfo(appID: bundleID, appName: app.localizedName ?? bundleID, title: string(window, kAXTitleAttribute) ?? "", frame: frame, displayID: base.display(for: frame)?.id, order: rank, isMinimized: minimized)
                entries.append((info, window, app.processIdentifier))
            }
        }
        // Stable: windows Core Graphics didn't list keep their app's order.
        let sorted = entries.enumerated().sorted { ($0.element.info.order, $0.offset) < ($1.element.info.order, $1.offset) }.map(\.element)
        var windows = sorted.map(\.info)
        for index in windows.indices { windows[index].order = index }
        return Live(snapshot: WindowSnapshot(displays: displays, windows: windows), elements: sorted.map(\.element), pids: sorted.map(\.pid))
    }

    /// Every display in Accessibility's top-left coordinates. The id is the
    /// display's vendor, model and serial number, which stays the same across
    /// reboots and ports; two identical monitors without serial numbers get
    /// `#2` and so on after the first.
    static func displays() -> [DisplayInfo] {
        let screens = NSScreen.screens
        let mainHeight = screens.first?.frame.height ?? 0
        var seen: [String: Int] = [:]
        return screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let display = CGDirectDisplayID(number.uint32Value)
            var id = "\(CGDisplayVendorNumber(display))-\(CGDisplayModelNumber(display))-\(CGDisplaySerialNumber(display))"
            let count = seen[id, default: 0] + 1
            seen[id] = count
            if count > 1 { id += "#\(count)" }
            return DisplayInfo(
                id: id,
                name: screen.localizedName,
                frame: flipped(screen.frame, mainHeight),
                visibleFrame: flipped(screen.visibleFrame, mainHeight),
                isMain: screen == screens.first,
                isBuiltIn: CGDisplayIsBuiltin(display) != 0
            )
        }
    }

    private static func flipped(_ rect: NSRect, _ mainHeight: CGFloat) -> WindowRect {
        WindowRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Normal-layer windows on screen, front to back, by process and bounds.
    private static func onScreenStack() -> [(pid: pid_t, frame: WindowRect)] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return (pid_t(pid), WindowRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height))
        }
    }

    private static func close(_ lhs: WindowRect, _ rhs: WindowRect) -> Bool {
        abs(lhs.x - rhs.x) < 2 && abs(lhs.y - rhs.y) < 2 && abs(lhs.width - rhs.width) < 2 && abs(lhs.height - rhs.height) < 2
    }

    // MARK: Moving

    static func arrange(_ placements: [WindowPlacement]) -> ArrangeResult {
        let live = live()
        let match = WindowMatcher.match(placements, to: live.snapshot.windows)
        var result = ArrangeResult(missing: match.missing.map { placements[$0].appName })
        // Back to front, so each raise lands the saved frontmost window on top.
        for assignment in match.assignments.reversed() {
            let placement = placements[assignment.placement]
            let window = live.snapshot.windows[assignment.window]
            let element = live.elements[assignment.window]
            if window.isMinimized && !placement.isMinimized {
                AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            var changed = window.isMinimized != placement.isMinimized
            if window.frame != placement.frame {
                if setFrame(element, placement.frame) {
                    changed = true
                } else if !result.failed.contains(placement.appName) {
                    result.failed.append(placement.appName)
                }
            }
            if placement.isMinimized {
                if !window.isMinimized { AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanTrue) }
            } else {
                AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            }
            if changed { result.moved += 1 }
        }
        // A raise orders windows within their app; bring the app of the
        // saved frontmost window forward too.
        if let front = match.assignments.first(where: { !placements[$0.placement].isMinimized }) {
            NSRunningApplication(processIdentifier: live.pids[front.window])?.activate()
        }
        return result
    }

    /// Position, size, then position again: moving a big window onto a
    /// smaller display first clamps it, and the second move puts it right.
    private static func setFrame(_ element: AXUIElement, _ frame: WindowRect) -> Bool {
        var point = CGPoint(x: frame.x, y: frame.y)
        var size = CGSize(width: frame.width, height: frame.height)
        guard let position = AXValueCreate(.cgPoint, &point), let extent = AXValueCreate(.cgSize, &size) else { return false }
        let moved = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        let sized = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, extent)
        let again = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        return moved == .success || sized == .success || again == .success
    }

    // MARK: Launching

    /// Opens the placements' apps that aren't running, without bringing them
    /// forward, and waits up to 8 seconds for their windows. Answers the
    /// names of the apps it opened.
    static func launchMissing(_ placements: [WindowPlacement]) async -> [String] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var wanted: [String: Int] = [:]
        var names: [String: String] = [:]
        for placement in placements where !running.contains(placement.appID) && !placement.isMinimized {
            wanted[placement.appID, default: 0] += 1
            names[placement.appID] = placement.appName
        }
        var opened: [String] = []
        for appID in wanted.keys.sorted() {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appID) else { continue }
            if await open(url) { opened.append(names[appID] ?? appID) }
        }
        guard !opened.isEmpty else { return [] }
        for _ in 0..<16 {
            try? await Task.sleep(for: .milliseconds(500))
            var counts: [String: Int] = [:]
            for window in live().snapshot.windows { counts[window.appID, default: 0] += 1 }
            if wanted.allSatisfy({ counts[$0.key, default: 0] >= $0.value }) { break }
        }
        return opened
    }

    private static func open(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
                continuation.resume(returning: app != nil && error == nil)
            }
        }
    }

    // MARK: Accessibility values

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        (copy(element, attribute) as? [AXUIElement]) ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        (copy(element, attribute) as? Bool) ?? false
    }

    private static func frame(_ window: AXUIElement) -> WindowRect? {
        guard let position = copy(window, kAXPositionAttribute), let extent = copy(window, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(extent) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable force_cast
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(extent as! AXValue, .cgSize, &size) else { return nil }
        // swiftlint:enable force_cast
        return WindowRect(x: point.x, y: point.y, width: size.width, height: size.height)
    }
}
#endif
