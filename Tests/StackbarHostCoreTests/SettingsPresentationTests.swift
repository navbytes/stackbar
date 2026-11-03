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

    func testIndexSummariesMapBackToTheirKind() {
        let samples: [Capability] = [
            .network(hosts: ["api.github.com"]), .files(paths: ["~/Notes"]), .run(commands: ["docker"]), .secret(name: "T"),
            .oauth(OAuthProvider(name: "github", authorizeURL: "https://github.com/login/oauth/authorize", tokenURL: "https://github.com/login/oauth/access_token", clientID: "x")),
            .clipboard, .power, .calendar, .context, .openURLs(schemes: ["https"]), .storage(megabytes: 50), .userServer(secret: "LiteLLM"), .windows, .apps, .keyLayer,
        ]
        for capability in samples {
            XCTAssertEqual(SettingsPresentation.Access(summary: capability.summary(resolver: resolver)), SettingsPresentation.Access(capability), capability.summary)
        }
        XCTAssertNil(SettingsPresentation.Access(summary: "Something new"))
    }
}
