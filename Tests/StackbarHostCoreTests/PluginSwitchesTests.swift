import Foundation
import XCTest
@testable import StackbarHostCore
import StackbarProtocol

final class PluginSwitchesTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "PluginSwitchesTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testOnUntilTurnedOffAndKeptByID() {
        let switches = PluginSwitches(defaults: defaults)
        XCTAssertTrue(switches.isOn("io.example.clock"))
        switches.set("io.example.clock", on: false)
        XCTAssertFalse(switches.isOn("io.example.clock"))
        XCTAssertTrue(PluginSwitches(defaults: defaults).offIDs.contains("io.example.clock"))
        switches.set("io.example.clock", on: true)
        XCTAssertTrue(switches.isOn("io.example.clock"))
    }

    func testAFileIsKnownByTheIDItLoadedAsSoItCanBeSkipped() {
        let switches = PluginSwitches(defaults: defaults)
        let file = URL(fileURLWithPath: "/tmp/plugins/Clock.swift")
        XCTAssertNil(switches.knownID(for: file))
        XCTAssertTrue(switches.isOn(file: file))
        XCTAssertTrue(switches.adopt("io.example.clock", for: file))
        switches.set("io.example.clock", on: false)
        XCTAssertFalse(switches.isOn(file: file))
        // A reinstall at another path is off too, once it loads as the same id.
        let moved = URL(fileURLWithPath: "/tmp/plugins/Clock-2.swift")
        XCTAssertFalse(switches.adopt("io.example.clock", for: moved))
    }

    func testOldPerFileSettingMovesToTheID() {
        let file = URL(fileURLWithPath: "/tmp/plugins/Clock.swift")
        defaults.set(true, forKey: "disabled." + file.path)
        let switches = PluginSwitches(defaults: defaults)
        XCTAssertFalse(switches.isOn(file: file))
        XCTAssertFalse(switches.adopt("io.example.clock", for: file))
        XCTAssertNil(defaults.object(forKey: "disabled." + file.path))
        XCTAssertFalse(switches.isOn("io.example.clock"))
    }

    func testForgettingAFileDropsItsID() {
        let switches = PluginSwitches(defaults: defaults)
        let file = URL(fileURLWithPath: "/tmp/plugins/Clock.swift")
        switches.adopt("io.example.clock", for: file)
        switches.forget(file: file)
        XCTAssertNil(switches.knownID(for: file))
    }

    func testForgettingTokensKeepsNamedSecrets() {
        let secrets = MemorySecretStore()
        let provider = OAuthProvider(name: "github", authorizeURL: "https://github.com/login/oauth/authorize", tokenURL: "https://github.com/login/oauth/access_token", clientID: "x")
        secrets.setSecret("{}", for: "oauth/io.example.clock/github")
        secrets.setSecret("t", for: "GITHUB_TOKEN")
        OAuthBroker.forgetTokens(of: "io.example.clock", providers: [provider], in: secrets)
        XCTAssertNil(secrets.secret("oauth/io.example.clock/github"))
        XCTAssertEqual(secrets.secret("GITHUB_TOKEN"), "t")
    }
}
