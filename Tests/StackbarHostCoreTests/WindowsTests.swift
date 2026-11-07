import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// Listing and arranging windows: the matcher, the simulated system, and the
/// capability check in front of both.
final class WindowsTests: XCTestCase {
    private func window(_ app: String, _ title: String = "", x: Double = 0, order: Int) -> WindowInfo {
        WindowInfo(appID: app, appName: app, title: title, frame: WindowRect(x: x, y: 0, width: 100, height: 100), order: order)
    }

    private func place(_ app: String, _ title: String = "", ordinal: Int = 0, x: Double) -> WindowPlacement {
        WindowPlacement(appID: app, title: title, ordinal: ordinal, frame: WindowRect(x: x, y: 0, width: 100, height: 100))
    }

    func testTitlesWinThenOrder() {
        let windows = [window("safari", "Docs", order: 1), window("safari", "Mail", order: 0), window("xcode", "Project", order: 2)]
        let placements = [place("safari", "Mail", ordinal: 0, x: 10), place("safari", "Renamed", ordinal: 1, x: 20), place("xcode", "Gone", x: 30), place("xcode", "Other", ordinal: 1, x: 40)]
        let match = WindowMatcher.match(placements, to: windows)
        XCTAssertEqual(match.assignments, [
            .init(placement: 0, window: 1), // same title
            .init(placement: 1, window: 0), // the only Safari window left
            .init(placement: 2, window: 2), // no title match: the frontmost Xcode window
        ])
        XCTAssertEqual(match.missing, [3], "Xcode has one window for two placements")
    }

    func testOrderGoesFrontToBackByOrdinal() {
        let windows = [window("term", order: 5), window("term", order: 2), window("term", order: 9)]
        let placements = [place("term", ordinal: 2, x: 3), place("term", ordinal: 0, x: 1), place("term", ordinal: 1, x: 2)]
        let match = WindowMatcher.match(placements, to: windows)
        XCTAssertEqual(match.assignments, [.init(placement: 0, window: 2), .init(placement: 1, window: 1), .init(placement: 2, window: 0)])
        XCTAssertTrue(match.missing.isEmpty)
    }

    func testCaptureNumbersEachAppsWindows() {
        let placements = WindowPlacement.capture(SimulatedSystem.sampleWindows())
        XCTAssertEqual(placements.map(\.appName), ["Xcode", "Safari", "Slack", "Safari"])
        XCTAssertEqual(placements.map(\.ordinal), [0, 0, 0, 1])
        XCTAssertTrue(placements[3].isMinimized)
    }

    func testSetupIDIgnoresDisplayOrder() {
        let sample = SimulatedSystem.sampleWindows()
        let reversed = WindowSnapshot(displays: sample.displays.reversed(), windows: sample.windows)
        XCTAssertEqual(sample.setupID, reversed.setupID)
        XCTAssertEqual(sample.display(for: WindowRect(x: 3000, y: 500, width: 400, height: 400))?.name, "Built-in Retina Display")
        XCTAssertEqual(sample.display(for: WindowRect(x: -900, y: 0, width: 100, height: 100))?.name, "Studio Display", "off screen: the nearest display")
    }

    func testSimulatedArrangeRestoresAndOpensApps() async throws {
        let system = SimulatedSystem()
        let saved = try await system.windows()
        let placements = WindowPlacement.capture(saved)
        // Undock: everything piles onto one spot, Slack quits.
        var scrambled = saved
        scrambled.windows = saved.windows.filter { $0.appName != "Slack" }.map { var window = $0; window.frame = WindowRect(x: 5, y: 5, width: 300, height: 300); return window }
        system.simulate(windows: scrambled)
        system.launchable["com.tinyspeck.slackmacgap"] = [WindowInfo(appID: "com.tinyspeck.slackmacgap", appName: "Slack", title: "Slack — navbytes", frame: WindowRect(x: 0, y: 0, width: 10, height: 10), order: 99)]

        let held = try await system.arrangeWindows(placements, launch: false)
        XCTAssertEqual(held.missing, ["Slack"])
        XCTAssertEqual(held.opened, [])

        let result = try await system.arrangeWindows(placements, launch: true)
        XCTAssertEqual(result.opened, ["Slack"])
        XCTAssertTrue(result.missing.isEmpty)
        XCTAssertEqual(result.moved, 1, "only Slack still had somewhere to go")
        let now = try await system.windows()
        XCTAssertEqual(now.windows.map(\.title), saved.windows.map(\.title), "the saved order is back")
        XCTAssertEqual(now.windows.map(\.frame), saved.windows.map(\.frame))
    }

    func testWindowCallsNeedTheCapability() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: .init(system: SimulatedSystem()))
        let bare = Manifest(id: "dev.test.bare", name: "Bare")
        for call: HostCall in [.windows, .arrangeWindows([], launch: false)] {
            guard case .failure(let message) = await services.handle(call, for: bare) else { return XCTFail("\(call) went through without .windows") }
            XCTAssertTrue(message.contains("add .windows"), message)
        }
        let granted = Manifest(id: "dev.test.windows", name: "Windows", capabilities: [.windows])
        guard case .value(let json?) = await services.handle(.windows, for: granted) else { return XCTFail("no windows") }
        let snapshot = try SystemCodec.decode(WindowSnapshot.self, from: json)
        XCTAssertEqual(snapshot.displays.count, 2)

        let tooMany = Array(repeating: WindowPlacement(appID: "x", frame: WindowRect(x: 0, y: 0, width: 1, height: 1)), count: WindowPlacement.maxPerCall + 1)
        guard case .failure = await services.handle(.arrangeWindows(tooMany, launch: false), for: granted) else { return XCTFail("placements are capped") }
        // A day of snapping: one move per keypress.
        for _ in 0..<120 {
            guard case .value = await services.handle(.arrangeWindows(WindowPlacement.capture(snapshot), launch: false), for: granted) else { return XCTFail("arrange failed") }
        }
        guard case .failure(let limited) = await services.handle(.arrangeWindows([], launch: false), for: granted) else { return XCTFail("arranging is rate limited") }
        XCTAssertTrue(limited.contains("120 a minute"), limited)
        XCTAssertEqual(Capability.windows.summary, "Sees which windows you have open and where, moves them, and opens apps")
    }
}
