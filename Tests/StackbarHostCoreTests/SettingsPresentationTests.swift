import Foundation
import XCTest
import StackbarProtocol
@testable import StackbarHostCore

final class SettingsPresentationTests: XCTestCase {
    let resolver = CommandResolver(directories: ["/usr/bin"], isExecutable: { $0 == "/usr/bin/docker" })

    func testPermissionsListGrantedThenPendingWithoutSecrets() {
        let rows = SettingsPresentation.permissions(
            granted: [.network(hosts: ["api.github.com"]), .secret(name: "GITHUB_TOKEN"), .clipboard],
            pending: [.run(commands: ["docker"])],
            resolver: resolver)
        XCTAssertEqual(rows.map(\.access), [.network, .clipboard, .run])
        XCTAssertEqual(rows.map(\.isPending), [false, false, true])
        XCTAssertEqual(rows[0].title, "api.github.com")
        XCTAssertEqual(rows[2].detail, "Runs /usr/bin/docker", "the detail names the program the user approves")
    }

    func testCapabilityAskedAgainShowsOnceAsPending() {
        let rows = SettingsPresentation.permissions(granted: [.clipboard], pending: [.clipboard], resolver: resolver)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].isPending)
    }

    func testEveryAccessHasASymbolTitleAndColour() {
        XCTAssertEqual(Set(SettingsPresentation.Access.allCases.map(\.title)).count, SettingsPresentation.Access.allCases.count)
        for access in SettingsPresentation.Access.allCases {
            XCTAssertFalse(access.symbol.isEmpty)
        }
    }

    func testStatusInWords() {
        typealias P = SettingsPresentation
        XCTAssertEqual(P.status(.running, isEnabled: false, waitingForApproval: true).tone, .off)
        XCTAssertEqual(P.status(.running, isEnabled: true, waitingForApproval: true).text, "Waiting for your approval")
        XCTAssertEqual(P.status(.running, isEnabled: true, waitingForApproval: false), .init(text: "Running", tone: .good))
        XCTAssertEqual(P.status(.running, isEnabled: true, waitingForApproval: false, missingSecrets: ["JIRA_TOKEN"]).text, "Needs JIRA_TOKEN")
        XCTAssertEqual(P.status(.restarting(attempt: 2, inSeconds: 4.4), isEnabled: true, waitingForApproval: false).text, "Restarting in 4s (attempt 2)")
        XCTAssertEqual(P.status(.failed("exit 1"), isEnabled: true, waitingForApproval: false).tone, .failed)
    }

    func testOverviewGroupsByAccessInOrder() {
        let groups = SettingsPresentation.overview([
            .init(id: "dev.t.pr", name: "PR Cockpit", granted: [.network(hosts: ["api.github.com"]), .secret(name: "GITHUB_TOKEN")]),
            .init(id: "dev.t.clip", name: "Clipboard", granted: [.clipboard], pending: [.network(hosts: ["example.com"])]),
            .init(id: "dev.t.clock", name: "Clock", granted: []),
        ])
        XCTAssertEqual(groups.map(\.access), [.network, .secret, .clipboard])
        XCTAssertEqual(groups[0].holders.map(\.pluginName), ["Clipboard", "PR Cockpit"])
        XCTAssertEqual(groups[0].holders.map(\.isPending), [true, false])
        XCTAssertEqual(groups[1].holders.first?.detail, "GITHUB_TOKEN")
    }

    func testSecretsListTheirPlugins() {
        let secrets = SettingsPresentation.secrets([
            (name: "PR Cockpit", secrets: ["GITHUB_TOKEN"]),
            (name: "GitHub", secrets: ["GITHUB_TOKEN", "GITHUB_TOKEN"]),
            (name: "Jira", secrets: ["JIRA_TOKEN"]),
        ])
        XCTAssertEqual(secrets.map(\.secret), ["GITHUB_TOKEN", "JIRA_TOKEN"])
        XCTAssertEqual(secrets[0].plugins, ["GitHub", "PR Cockpit"])
    }

    /// One capability of each kind. The switch has no default, so a new
    /// capability does not compile until it is sampled here.
    private func sample(_ kind: Capability.Kind) -> Capability {
        switch kind {
        case .network: return .network(hosts: ["api.github.com"])
        case .files: return .files(paths: ["~/Notes"])
        case .run: return .run(commands: ["docker"])
        case .secret: return .secret(name: "T")
        case .oauth: return .oauth(OAuthProvider(name: "github", authorizeURL: "https://github.com/login/oauth/authorize", tokenURL: "https://github.com/login/oauth/access_token", clientID: "x"))
        case .clipboard: return .clipboard
        case .power: return .power
        case .calendar: return .calendar
        case .context: return .context
        case .openURLs: return .openURLs(schemes: ["https"])
        case .storage: return .storage(megabytes: 50)
        case .userServer: return .userServer(secret: "LiteLLM")
        case .windows: return .windows
        case .apps: return .apps
        case .keyLayer: return .keyLayer
        case .reminders: return .reminders
        case .fileSearch: return .fileSearch
        case .systemActions: return .systemActions
        case .textExpansion: return .textExpansion
        case .menus: return .menus
        case .calendarWrite: return .calendarWrite
        case .terminal: return .terminal
        case .screenText: return .screenText
        case .sensors: return .sensors
        }
    }

    func testEveryKindRoundTrips() {
        for kind in Capability.Kind.allCases {
            XCTAssertEqual(sample(kind).kind, kind)
        }
    }

    func testIndexSummariesMapBackToTheirKind() {
        for kind in Capability.Kind.allCases {
            let capability = sample(kind)
            XCTAssertEqual(SettingsPresentation.Access(summary: capability.summary(resolver: resolver)), SettingsPresentation.Access(capability), capability.summary)
        }
        XCTAssertEqual(SettingsPresentation.Access(summary: Capability.terminal.summary), .run)
        XCTAssertNil(SettingsPresentation.Access(summary: "Something new"))
    }

    func testStorePermissionsReadTheIndexKinds() {
        let capabilities: [Capability] = [.terminal, .sensors, .menus, .openURLs(schemes: ["https"])]
        var entry = PluginIndex.Entry(id: "x", name: "X", version: "1.0.0", publisher: "p", bundle: "b", sha256: "s",
                                      capabilities: capabilities.map(\.summary), capabilityKinds: capabilities.map(\.kind.rawValue))
        XCTAssertEqual(SettingsPresentation.storePermissions(entry).map(\.access), [.run, .power, .windows, .links])
        XCTAssertEqual(SettingsPresentation.storePermissions(entry).map(\.summary), entry.capabilities)

        // A summary reworded later still shows its kind, because the index says it.
        entry.capabilities[0] = "Starts a command in Terminal"
        XCTAssertEqual(SettingsPresentation.storePermissions(entry).first?.access, .run)

        // An index from before kinds, or with a kind this app doesn't know, falls back to the words.
        entry.capabilityKinds = nil
        XCTAssertNil(SettingsPresentation.storePermissions(entry).first?.access)
        entry.capabilities[0] = Capability.terminal.summary
        entry.capabilityKinds = ["somethingNew", "sensors", "menus", "openURLs"]
        XCTAssertEqual(SettingsPresentation.storePermissions(entry).first?.access, .run)
    }
}
