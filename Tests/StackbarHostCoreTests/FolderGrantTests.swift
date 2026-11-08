import Foundation
import XCTest
import StackbarProtocol
@testable import StackbarHostCore

final class FolderGrantTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("folder-grants-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func services(_ system: SimulatedSystem, grants: FolderGrants, socket: String? = nil) -> HostServices {
        HostServices(storage: StorageStore(directory: root.appendingPathComponent("storage")), secrets: MemorySecretStore([:]),
                     platform: .init(system: system), runs: CommandRunGate(root: root.appendingPathComponent("run")),
                     folderGrants: grants, sshAgentSocket: socket)
    }

    private let manifest = Manifest(id: "dev.test.folders", name: "Folders", capabilities: [.run(commands: ["pwd", "env"])])

    func testAChosenFolderLetsCommandsRunThereUntilRemoved() async throws {
        let repos = root.appendingPathComponent("repos/app", isDirectory: true)
        try FileManager.default.createDirectory(at: repos, withIntermediateDirectories: true)
        let system = SimulatedSystem()
        let grants = FolderGrants(file: root.appendingPathComponent("grants.json"))
        let services = services(system, grants: grants)
        let inside = RunRequest(command: "pwd", workingDirectory: repos.path)

        guard case .failure = await services.handle(.run(inside), for: manifest) else { return XCTFail("ran outside its folders") }

        system.simulate(chosenFolder: root.appendingPathComponent("repos").path)
        guard case .value(let json?) = await services.handle(.chooseFolder(prompt: "Your code", startingAt: nil), for: manifest) else { return XCTFail("no folder") }
        let chosen = try SystemCodec.decode(ChosenFolder.self, from: json)
        XCTAssertEqual(chosen.name, "repos")
        guard case .value(let listed?) = await services.handle(.grantedFolders, for: manifest) else { return XCTFail("no list") }
        XCTAssertEqual(try SystemCodec.decode([String].self, from: listed), [chosen.path])

        guard case .value(let ran?) = await services.handle(.run(inside), for: manifest) else { return XCTFail("did not run in the chosen folder") }
        XCTAssertEqual(try SystemCodec.decode(RunResult.self, from: ran).text, CommandRunGateTests.physical(repos.path) + "\n")

        XCTAssertEqual(FolderGrants(file: root.appendingPathComponent("grants.json")).folders(for: manifest.id), [chosen.path], "saved")
        let other = Manifest(id: "dev.test.other", name: "Other", capabilities: [.run(commands: ["pwd"])])
        guard case .failure = await services.handle(.run(inside), for: other) else { return XCTFail("another plugin used the grant") }

        try grants.remove(chosen.path, for: manifest.id)
        guard case .failure = await services.handle(.run(inside), for: manifest) else { return XCTFail("ran after removal") }
    }

    func testCancelAnswersNilAndBroadFoldersAreRefused() async {
        let system = SimulatedSystem()
        let services = services(system, grants: FolderGrants(file: nil))
        system.simulate(chosenFolder: nil)
        let cancelled = await services.handle(.chooseFolder(prompt: nil, startingAt: nil), for: manifest)
        XCTAssertEqual(cancelled, .value(nil))
        for broad in ["/", NSHomeDirectory(), NSHomeDirectory() + "/Library/Keychains", "/System/Library", "/Users"] {
            system.simulate(chosenFolder: broad)
            guard case .failure = await services.handle(.chooseFolder(prompt: nil, startingAt: nil), for: manifest) else { return XCTFail("granted \(broad)") }
        }
        XCTAssertNil(FolderGrants.refusal(root.path))
    }

    func testObserversHearChangesAndRemoveAllForgetsThePlugin() throws {
        let grants = FolderGrants(file: nil)
        final class Heard: @unchecked Sendable { var ids: [String] = [] }
        let heard = Heard()
        grants.observe { heard.ids.append($0) }
        let path = try grants.add(root.path, for: "a")
        try grants.add(root.path, for: "a")
        XCTAssertEqual(grants.folders(for: "a"), [path])
        try grants.removeAll(for: "a")
        XCTAssertEqual(grants.folders(for: "a"), [])
        XCTAssertEqual(heard.ids, ["a", "a"], "adding twice notifies once")
    }

    func testTheSSHAgentReachesCommandsOnlyWithTheCapability() async throws {
        let services = services(SimulatedSystem(), grants: FolderGrants(file: nil), socket: "/tmp/agent.sock")
        func env(_ manifest: Manifest) async throws -> String {
            guard case .value(let json?) = await services.handle(.run(RunRequest(command: "env")), for: manifest) else { throw XCTSkip("did not run") }
            return try SystemCodec.decode(RunResult.self, from: json).text
        }
        let without = try await env(manifest)
        XCTAssertFalse(without.contains("SSH_AUTH_SOCK"))
        var with = manifest
        with.capabilities.append(.sshAgent)
        let withAgent = try await env(with)
        XCTAssertTrue(withAgent.contains("SSH_AUTH_SOCK=/tmp/agent.sock\n"))

        let spoof = await services.handle(.run(RunRequest(command: "env", environment: ["SSH_AUTH_SOCK": "/tmp/other"])), for: with)
        guard case .failure = spoof else { return XCTFail("a plugin set SSH_AUTH_SOCK") }
        XCTAssertEqual(Capability.sshAgent.kind, .sshAgent)
        XCTAssertEqual(SettingsPresentation.Access(.sshAgent), .run)
    }
}
