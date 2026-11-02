import Foundation

// Values for the window calls (protocol 13): what is on screen, and where to
// put it back. The host reads and moves windows through Accessibility, so
// plugins stay sandboxed; these types cross the wire as JSON inside
// `HostResult.value`.

/// A rectangle in global screen points, origin at the top-left of the main
/// display and y growing down: the space Accessibility and Core Graphics use,
/// not AppKit's flipped one.
public struct WindowRect: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px < x + width && py >= y && py < y + height
    }

    /// The area this rectangle shares with `other`, 0 when they don't meet.
    public func overlap(_ other: WindowRect) -> Double {
        let width = min(x + self.width, other.x + other.width) - max(x, other.x)
        let height = min(y + self.height, other.y + other.height) - max(y, other.y)
        return width > 0 && height > 0 ? width * height : 0
    }
}

/// A connected display.
public struct DisplayInfo: Codable, Equatable, Sendable {
    /// The display's UUID: the same display keeps it across reboots and ports.
    public var id: String
    /// What System Settings calls it ("Studio Display", "Built-in Retina Display").
    public var name: String
    public var frame: WindowRect
    /// The frame without the menu bar and the Dock.
    public var visibleFrame: WindowRect
    /// The display with the menu bar.
    public var isMain: Bool
    public var isBuiltIn: Bool

    public init(id: String, name: String, frame: WindowRect, visibleFrame: WindowRect? = nil, isMain: Bool = false, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame ?? frame
        self.isMain = isMain
        self.isBuiltIn = isBuiltIn
    }
}

/// One window of a regular (Dock) app.
public struct WindowInfo: Codable, Equatable, Sendable {
    public var appID: String
    public var appName: String
    /// Empty when the app gives the window none.
    public var title: String
    public var frame: WindowRect
    /// The display holding most of the window, or `nil` when it is off screen.
    public var displayID: String?
    /// Front to back across all apps: 0 is the frontmost window.
    public var order: Int
    public var isMinimized: Bool

    public init(appID: String, appName: String, title: String = "", frame: WindowRect, displayID: String? = nil, order: Int = 0, isMinimized: Bool = false) {
        self.appID = appID
        self.appName = appName
        self.title = title
        self.frame = frame
        self.displayID = displayID
        self.order = order
        self.isMinimized = isMinimized
    }
}

/// The displays and windows now, answered by `HostCall.windows`.
public struct WindowSnapshot: Codable, Equatable, Sendable {
    public var displays: [DisplayInfo]
    /// Front to back.
    public var windows: [WindowInfo]

    public init(displays: [DisplayInfo] = [], windows: [WindowInfo] = []) {
        self.displays = displays
        self.windows = windows.sorted { $0.order < $1.order }
    }

    /// Names this monitor setup: the display ids, sorted and joined. The same
    /// displays give the same id whichever port they are in.
    public var setupID: String { WindowSnapshot.setupID(displays.map(\.id)) }

    public static func setupID(_ displayIDs: [String]) -> String {
        displayIDs.sorted().joined(separator: "+")
    }

    /// The display holding most of `frame`, else the one its centre is
    /// nearest to.
    public func display(for frame: WindowRect) -> DisplayInfo? {
        let best = displays.max { $0.frame.overlap(frame) < $1.frame.overlap(frame) }
        if let best, best.frame.overlap(frame) > 0 { return best }
        return displays.min { distance($0.frame, frame) < distance($1.frame, frame) }
    }

    private func distance(_ display: WindowRect, _ frame: WindowRect) -> Double {
        let dx = display.midX - frame.midX
        let dy = display.midY - frame.midY
        return dx * dx + dy * dy
    }
}

/// Where one saved window goes.
public struct WindowPlacement: Codable, Equatable, Sendable {
    public var appID: String
    /// For the user, and for saying what was missing.
    public var appName: String
    /// Matched first: a window with this title gets this frame.
    public var title: String
    /// Then by order: this window's place among the app's saved windows,
    /// front first.
    public var ordinal: Int
    public var frame: WindowRect
    public var isMinimized: Bool

    public init(appID: String, appName: String = "", title: String = "", ordinal: Int = 0, frame: WindowRect, isMinimized: Bool = false) {
        self.appID = appID
        self.appName = appName.isEmpty ? appID : appName
        self.title = title
        self.ordinal = ordinal
        self.frame = frame
        self.isMinimized = isMinimized
    }

    /// The placements that put every window in `snapshot` back where it is
    /// now, front to back.
    public static func capture(_ snapshot: WindowSnapshot) -> [WindowPlacement] {
        var seen: [String: Int] = [:]
        return snapshot.windows.map { window in
            let ordinal = seen[window.appID, default: 0]
            seen[window.appID] = ordinal + 1
            return WindowPlacement(appID: window.appID, appName: window.appName, title: window.title, ordinal: ordinal, frame: window.frame, isMinimized: window.isMinimized)
        }
    }

    /// At most this many placements in one `arrangeWindows` call.
    public static let maxPerCall = 200
}

/// What `arrangeWindows` did.
public struct ArrangeResult: Codable, Equatable, Sendable {
    /// Windows moved or resized.
    public var moved: Int
    /// Apps opened because they weren't running, by name.
    public var opened: [String]
    /// Placements that had no window to go to, by app name.
    public var missing: [String]
    /// Windows that refused to move (full screen, or the app said no), by app name.
    public var failed: [String]

    public init(moved: Int = 0, opened: [String] = [], missing: [String] = [], failed: [String] = []) {
        self.moved = moved
        self.opened = opened
        self.missing = missing
        self.failed = failed
    }
}
