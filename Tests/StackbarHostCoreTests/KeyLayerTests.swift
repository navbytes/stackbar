import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// The app calls and the key layer: how a press is routed, who holds a
/// trigger, the simulated system, and the capability checks.
final class KeyLayerTests: XCTestCase {
    private let safari = "com.apple.Safari"
    private let slack = "com.tinyspeck.slackmacgap"
    private let spotify = "com.spotify.client"
    private let xcode = "com.apple.dt.Xcode"

    private func apps(front: String?, hidden: Set<String> = []) -> [RunningApp] {
        SimulatedSystem.sampleApps().map { var app = $0; app.isActive = app.id == front; app.isHidden = hidden.contains(app.id); return app }
    }

    private func layers(_ layer: KeyLayer, plugin: String = "dev.test.switcher") -> [KeyLayerRegistry.Registration] {
        [KeyLayerRegistry.Registration(pluginID: plugin, pluginName: "Switcher", layer: layer)]
    }

    private var sample: KeyLayer {
        KeyLayer(bindings: [
            KeyBinding(key: "s", apps: [safari, slack, spotify]),
            KeyBinding(key: "x", apps: [xcode]),
            KeyBinding(key: "m", apps: ["com.apple.Mail"], launch: true),
            KeyBinding(key: "n", apps: ["com.apple.Notes"]),
        ], assignCommand: "assign")
    }

    private func route(_ key: String, held: Set<KeyLayerTrigger> = [.rightCommand], layer: KeyLayer? = nil, front: String?) -> KeyLayerRouter.Decision {
        KeyLayerRouter.route(key: key, held: held, layers: layers(layer ?? sample), running: apps(front: front))
    }

    func testOnlyBoundKeysWithTheTriggerHeldAreTaken() {
        XCTAssertEqual(route("s", held: [], front: xcode), .passThrough, "no trigger held")
        XCTAssertEqual(route("s", held: [.rightOption], front: xcode), .passThrough, "another modifier")
        XCTAssertEqual(route("c", front: xcode), .passThrough, "Right ⌘ + C still copies")
        XCTAssertEqual(route("S", front: xcode), .activate(safari), "case doesn't matter")
    }

    func testSameLetterCyclesInOrder() {
        XCTAssertEqual(route("s", front: xcode), .activate(safari), "the first app on the key")
        XCTAssertEqual(route("s", front: safari), .activate(slack))
        XCTAssertEqual(route("s", front: slack), .activate(spotify))
        XCTAssertEqual(route("s", front: spotify), .activate(safari), "wraps around")
    }

    func testSecondPressFollowsTheLayer() {
        XCTAssertEqual(route("x", front: xcode), .hide(xcode))
        var layer = sample
        layer.secondPress = .cycleWindows
        XCTAssertEqual(route("x", layer: layer, front: xcode), .cycleWindows(xcode))
        layer.secondPress = .stay
        XCTAssertEqual(route("x", layer: layer, front: xcode), .swallow)
    }

    func testAppsThatArentRunningOpenOnlyWhenAllowed() {
        XCTAssertEqual(route("m", front: xcode), .launch("com.apple.Mail"))
        XCTAssertEqual(route("n", front: xcode), .swallow, "bound, so it doesn't reach the app as ⌘N")
    }

    func testAssignChordNamesTheFrontmostApp() {
        XCTAssertEqual(route("k", held: [.rightCommand, .rightOption], front: slack), .assign(pluginID: "dev.test.switcher", command: "assign", key: "k", app: slack))
        XCTAssertEqual(route(";", held: [.rightCommand, .rightOption], front: slack), .passThrough, "only letters and digits")
        var layer = sample
        layer.assignCommand = nil
        XCTAssertEqual(route("k", held: [.rightCommand, .rightOption], layer: layer, front: slack), .swallow)
        layer.trigger = .rightOption
        layer.assignCommand = "assign"
        XCTAssertEqual(route("k", held: [.rightOption, .rightCommand], layer: layer, front: slack), .assign(pluginID: "dev.test.switcher", command: "assign", key: "k", app: slack), "a Right ⌥ layer assigns with Right ⌘")
    }

    func testFirstPluginOnATriggerListensAndTheOtherWaits() throws {
        let registry = KeyLayerRegistry()
        try registry.set(sample, pluginID: "dev.a", pluginName: "A")
        try registry.set(KeyLayer(bindings: [KeyBinding(key: "s", apps: [spotify])]), pluginID: "dev.b", pluginName: "B")
        XCTAssertEqual(registry.listening.map(\.pluginID), ["dev.a"])
        XCTAssertEqual(registry.conflict(for: "dev.b"), "A")
        XCTAssertNil(registry.conflict(for: "dev.a"))

        try registry.set(KeyLayer(trigger: .rightOption, bindings: []), pluginID: "dev.c", pluginName: "C")
        XCTAssertEqual(registry.listening.map(\.pluginID), ["dev.a", "dev.c"], "another trigger listens alongside")

        try registry.set(nil, pluginID: "dev.a", pluginName: "A")
        XCTAssertEqual(registry.listening.map(\.pluginID), ["dev.b", "dev.c"], "B takes Right ⌘ once A lets go")
        XCTAssertNil(registry.conflict(for: "dev.b"))
    }

    func testBadLayersAreRefused() {
        let registry = KeyLayerRegistry()
        let doubled = KeyLayer(bindings: [KeyBinding(key: "a", apps: [safari]), KeyBinding(key: "a", apps: [xcode])])
        XCTAssertThrowsError(try registry.set(doubled, pluginID: "dev.a", pluginName: "A"))
        XCTAssertThrowsError(try registry.set(KeyLayer(bindings: [KeyBinding(key: "ab", apps: [safari])]), pluginID: "dev.a", pluginName: "A"))
        XCTAssertThrowsError(try registry.set(KeyLayer(bindings: [KeyBinding(key: "a", apps: [])]), pluginID: "dev.a", pluginName: "A"))
        XCTAssertTrue(registry.isEmpty)
    }

    func testSimulatedPressesSwitchHideAndOpen() async throws {
        let system = SimulatedSystem()
        let status = try system.setKeyLayer(sample, pluginID: "dev.a", pluginName: "A")
        XCTAssertTrue(status.listening)

        await system.pressKeyLayer("x")
        XCTAssertEqual(system.currentApps.first(where: \.isActive)?.id, xcode)
        await system.pressKeyLayer("x")
        XCTAssertTrue(system.currentApps.first { $0.id == xcode }!.isHidden, "a second press hides it")
        XCTAssertNotEqual(system.currentApps.first(where: \.isActive)?.id, xcode)
        await system.pressKeyLayer("x")
        XCTAssertEqual(system.currentApps.first(where: \.isActive)?.id, xcode, "and a third brings it back")
        XCTAssertFalse(system.currentApps.first { $0.id == xcode }!.isHidden)

        system.applications["Mail"] = "com.apple.Mail"
        await system.pressKeyLayer("m")
        XCTAssertEqual(system.currentApps.first(where: \.isActive)?.id, "com.apple.Mail")
        XCTAssertTrue(system.appActions.contains("launch com.apple.Mail"))

        _ = try system.setKeyLayer(nil, pluginID: "dev.a", pluginName: "A")
        let afterRemoval = await system.pressKeyLayer("x")
        XCTAssertEqual(afterRemoval, .passThrough)
        XCTAssertEqual(system.keyLayerStatus(pluginID: "dev.a"), .off)
    }

    func testCallsNeedTheirCapabilitiesAndStoppingLetsGo() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let system = SimulatedSystem()
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: .init(system: system))
        let bare = Manifest(id: "dev.test.bare", name: "Bare")
        for call: HostCall in [.runningApps, .activateApp(safari, launch: false), .hideApp(safari)] {
            guard case .failure(let message) = await services.handle(call, for: bare) else { return XCTFail("\(call) went through without .apps") }
            XCTAssertTrue(message.contains("add .apps"), message)
        }
        for call: HostCall in [.setKeyLayer(sample), .keyLayerStatus] {
            guard case .failure(let message) = await services.handle(call, for: bare) else { return XCTFail("\(call) went through without .keyLayer") }
            XCTAssertTrue(message.contains("add .keyLayer"), message)
        }
        guard case .value = await services.handle(.setKeyLayer(nil), for: bare) else { return XCTFail("letting go needs nothing") }

        let granted = Manifest(id: "dev.test.switcher", name: "Switcher", capabilities: [.apps, .keyLayer])
        guard case .value(let json?) = await services.handle(.runningApps, for: granted) else { return XCTFail("no apps") }
        XCTAssertEqual(try SystemCodec.decode([RunningApp].self, from: json).count, 5)
        guard case .ok = await services.handle(.activateApp(slack, launch: false), for: granted) else { return XCTFail("switch failed") }
        XCTAssertEqual(system.currentApps.first(where: \.isActive)?.id, slack)
        guard case .failure = await services.handle(.activateApp("com.example.missing", launch: false), for: granted) else { return XCTFail("not running") }

        guard case .value(let statusJSON?) = await services.handle(.setKeyLayer(sample), for: granted) else { return XCTFail("layer refused") }
        XCTAssertTrue(try SystemCodec.decode(KeyLayerStatus.self, from: statusJSON).listening)
        XCTAssertEqual(system.keyLayers.listening.map(\.pluginName), ["Switcher"])
        services.release(pluginID: granted.id)
        XCTAssertTrue(system.keyLayers.isEmpty, "a stopped plugin's layer goes with it")

        for _ in 0..<118 { _ = await services.handle(.hideApp(safari), for: granted) }
        guard case .failure(let limited) = await services.handle(.hideApp(safari), for: granted) else { return XCTFail("switching is rate limited") }
        XCTAssertTrue(limited.contains("120 a minute"), limited)
    }

    func testLayerAndStatusRoundTrip() throws {
        let decoded = try SystemCodec.decode(KeyLayer.self, from: SystemCodec.encode(sample))
        XCTAssertEqual(decoded, sample)
        let status = KeyLayerStatus(listening: false, needsAccessibility: true, secureInputApp: "1Password")
        XCTAssertEqual(try SystemCodec.decode(KeyLayerStatus.self, from: SystemCodec.encode(status)), status)
    }
}
