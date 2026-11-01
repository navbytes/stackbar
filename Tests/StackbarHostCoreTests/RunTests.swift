import Foundation
import XCTest
import StackbarProtocol
@testable import StackbarHostCore

final class Messages: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [HostMessage] = []
    func add(_ message: HostMessage) { lock.withLock { list.append(message) } }
    var all: [HostMessage] { lock.withLock { list } }
    var exit: RunExit? {
        all.lazy.compactMap { if case .runExit(_, let exit) = $0 { return exit } else { return nil } }.first
    }

    func output(_ channel: RunChannel) -> String {
        all.compactMap { message -> Data? in
            if case .runOutput(_, channel, let data) = message { return data }
            return nil
        }.reduce(into: "") { $0 += String(decoding: $1, as: UTF8.self) }
    }
}

final class CommandResolverTests: XCTestCase {
    func testBareNamesUseTheFixedSearchPathOnly() {
        let installed: Set<String> = ["/usr/local/bin/brew", "/opt/homebrew/bin/brew", "/usr/bin/git", "/Users/me/bin/evil"]
        let resolver = CommandResolver(isExecutable: { installed.contains($0) })
        XCTAssertEqual(resolver.resolve("brew"), "/opt/homebrew/bin/brew", "earlier directories win")
        XCTAssertEqual(resolver.resolve("git"), "/usr/bin/git")
        XCTAssertNil(resolver.resolve("evil"), "the user's PATH is never searched")
        XCTAssertEqual(resolver.resolve("/Users/me/bin/evil"), "/Users/me/bin/evil", "an absolute path is declared as it is")
        XCTAssertEqual(resolver.resolve("/usr/bin/../bin/git"), "/usr/bin/git")
        XCTAssertNil(resolver.resolve("bin/git"))
        XCTAssertNil(resolver.resolve(".."))
        XCTAssertNil(resolver.resolve(""))
        XCTAssertEqual(resolver.resolve(all: ["brew", "evil"]), ["brew": "/opt/homebrew/bin/brew"])
    }

    func testInterpretersAreFlagged() {
        for name in ["sh", "/bin/zsh", "python3", "python3.12", "/opt/homebrew/bin/node", "osascript", "env"] {
            XCTAssertTrue(CommandResolver.isInterpreter(name), name)
        }
        for name in ["brew", "git", "docker", "/usr/bin/pmset"] {
            XCTAssertFalse(CommandResolver.isInterpreter(name), name)
        }
    }

    func testTheSheetShowsResolvedPathsAndFlagsInterpreters() {
        let resolver = CommandResolver(isExecutable: { ["/usr/bin/git", "/bin/sh"].contains($0) })
        let summary = Capability.run(commands: ["git", "sh", "missing"]).summary(resolver: resolver)
        XCTAssertEqual(summary, "Runs /usr/bin/git, /bin/sh (can run any program), missing (not installed)")
    }
}

final class CommandLedgerTests: XCTestCase {
    final class Paths: @unchecked Sendable {
        private let lock = NSLock()
        private var installed: Set<String>
        init(_ installed: Set<String>) { self.installed = installed }
        func set(_ installed: Set<String>) { lock.withLock { self.installed = installed } }
        func contains(_ path: String) -> Bool { lock.withLock { installed.contains(path) } }
    }

    func testApprovalRecordsPathsAndAMoveNeedsApprovalAgain() throws {
        let paths = Paths(["/usr/local/bin/brew"])
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("approvals.json")
        let ledger = CapabilityLedger(file: file, resolver: CommandResolver(isExecutable: { paths.contains($0) }))
        let manifest = Manifest(id: "dev.test.brew", name: "Brew", capabilities: [.network("formulae.brew.sh"), .run(commands: ["brew"])])
        try ledger.approve(manifest)
        XCTAssertEqual(ledger.approvedCommandPaths(for: manifest.id), ["brew": "/usr/local/bin/brew"])
        XCTAssertEqual(ledger.review(manifest), .approved(granted: manifest.capabilities))

        // Reloaded from disk, the paths are still there.
        let reloaded = CapabilityLedger(file: file, resolver: CommandResolver(isExecutable: { paths.contains($0) }))
        XCTAssertEqual(reloaded.approvedCommandPaths(for: manifest.id), ["brew": "/usr/local/bin/brew"])

        // Homebrew moved to /opt/homebrew: brew resolves elsewhere now.
        paths.set(["/opt/homebrew/bin/brew"])
        XCTAssertEqual(ledger.movedCommands(manifest), ["brew"])
        XCTAssertEqual(ledger.review(manifest), .needsApproval(added: [.run(commands: ["brew"])], removed: [], granted: [.network("formulae.brew.sh")], isNew: false))
        try ledger.approve(manifest)
        XCTAssertEqual(ledger.review(manifest), .approved(granted: manifest.capabilities))

        // Uninstalled is not moved: the run fails saying it is not installed.
        paths.set([])
        XCTAssertEqual(ledger.movedCommands(manifest), [])
    }
}

final class CommandRunGateTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("run-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func gate(_ limits: CommandRunGate.Limits = .init()) -> CommandRunGate {
        CommandRunGate(root: root, limits: limits)
    }

    private let grant = CommandRunGate.Grant(pluginID: "dev.test.run")

    private func run(_ gate: CommandRunGate, _ command: String, _ arguments: [String] = [], timeout: Double = 10, environment: [String: String] = [:], workingDirectory: String? = nil, grant: CommandRunGate.Grant? = nil) async throws -> RunResult {
        let request = RunRequest(command: command, arguments: arguments, workingDirectory: workingDirectory, environment: environment, timeout: timeout)
        return try await gate.run(request, id: 1, grant: grant ?? self.grant).get()
    }

    func testRunsWithArgumentsExactlyAndNoShell() async throws {
        let result = try await run(gate(), "echo", ["$HOME", "a b", "; ls"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.text, "$HOME a b ; ls\n")
        XCTAssertFalse(result.truncated)
        XCTAssertFalse(result.timedOut)
    }

    func testExitStatusStdinAndStderr() async throws {
        let gate = gate()
        let request = RunRequest(command: "sh", arguments: ["-c", "cat; echo oops >&2; exit 3"], input: Data("from stdin".utf8))
        let result = try await gate.run(request, id: 1, grant: grant).get()
        XCTAssertEqual(result.status, 3)
        XCTAssertEqual(result.text, "from stdin")
        XCTAssertEqual(result.errorText, "oops\n")
        XCTAssertFalse(result.succeeded)
        let record = try XCTUnwrap(gate.recentRuns(pluginID: grant.pluginID).first)
        XCTAssertEqual(record.status, 3)
        XCTAssertEqual(record.stdoutBytes, 10)
        XCTAssertEqual(record.stderrBytes, 5)
        XCTAssertTrue(record.path.hasSuffix("/sh"))
        XCTAssertEqual(gate.activeRuns(pluginID: grant.pluginID), 0)
    }

    func testEnvironmentIsTheHostsMinimalOnePlusThePlugins() async throws {
        setenv("STACKBAR_TEST_LEAK", "secret", 1)
        defer { unsetenv("STACKBAR_TEST_LEAK") }
        let result = try await run(gate(), "env", environment: ["MY_VAR": "1"])
        let lines = Set(result.text.split(separator: "\n").map(String.init))
        XCTAssertTrue(lines.contains("PATH=" + CommandResolver.searchPath.joined(separator: ":")))
        XCTAssertTrue(lines.contains("MY_VAR=1"))
        XCTAssertTrue(lines.contains("LANG=en_US.UTF-8"))
        XCTAssertTrue(lines.contains("TMPDIR=" + root.appendingPathComponent("dev.test.run/tmp").path + "/"))
        XCTAssertFalse(result.text.contains("STACKBAR_TEST_LEAK"))
        XCTAssertEqual(lines.count, 5, "PATH, HOME, LANG, TMPDIR and MY_VAR only: \(lines)")
    }

    func testReservedVariablesAreRefused() async {
        for name in ["PATH", "HOME", "TMPDIR", "DYLD_INSERT_LIBRARIES", "LD_PRELOAD"] {
            let result = await gate().run(RunRequest(command: "env", environment: [name: "/x"]), id: 1, grant: grant)
            XCTAssertEqual(try? result.get(), nil, name)
        }
    }

    func testWorkingDirectoryIsThePluginsFolderOrAGrantedOne() async throws {
        let gate = gate()
        let home = try await run(gate, "pwd")
        XCTAssertEqual(home.text, Self.physical(root.appendingPathComponent("dev.test.run").path) + "\n")

        let project = root.appendingPathComponent("project/src", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let granted = CommandRunGate.Grant(pluginID: grant.pluginID, folders: [root.appendingPathComponent("project").path])
        let inside = try await run(gate, "pwd", workingDirectory: project.path, grant: granted)
        XCTAssertEqual(inside.text, Self.physical(project.path) + "\n")

        for outside in ["/", project.path + "/../../..", "relative"] {
            let refused = await gate.run(RunRequest(command: "pwd", workingDirectory: outside), id: 1, grant: granted)
            guard case .failure(let refusal) = refused else { return XCTFail("\(outside) was allowed") }
            XCTAssertEqual(refusal.kind, .invalid)
        }
    }

    /// What `pwd` prints: macOS's temporary folder is under /private, which
    /// Foundation's symlink resolution leaves out.
    static func physical(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    func testTimeoutStopsTheWholeProcessGroup() async throws {
        let started = Date()
        let result = try await run(gate(), "sh", ["-c", "sleep 30 & sleep 30"], timeout: 0.5)
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "the background sleep held the pipe open")
    }

    func testOutputIsCutAtTheLimit() async throws {
        var limits = CommandRunGate.Limits()
        limits.maxOutput = 1000
        let result = try await run(gate(limits), "head", ["-c", "100000", "/dev/zero"])
        XCTAssertEqual(result.stdout.count, 1000)
        XCTAssertTrue(result.truncated)
    }

    func testRefusals() async {
        let gate = gate()
        func refusal(_ request: RunRequest, _ grant: CommandRunGate.Grant? = nil) async -> CommandRunGate.Refusal? {
            if case .failure(let refusal) = await gate.run(request, id: 1, grant: grant ?? self.grant) { return refusal }
            return nil
        }
        let missing = await refusal(RunRequest(command: "definitely-not-installed"))
        XCTAssertEqual(missing?.kind, .notInstalled)
        XCTAssertTrue(missing?.description.contains("/opt/homebrew/bin") == true)
        let tooLong = await refusal(RunRequest(command: "echo", timeout: 601))
        XCTAssertEqual(tooLong?.kind, .invalid)
        let relative = await refusal(RunRequest(command: "./echo"))
        XCTAssertEqual(relative?.kind, .invalid)
        let moved = await refusal(RunRequest(command: "echo"), CommandRunGate.Grant(pluginID: "dev.test.run", approvedPaths: ["echo": "/somewhere/else/echo"]))
        XCTAssertEqual(moved?.kind, .moved)
        XCTAssertTrue(moved?.description.contains("approve") == true)
    }

    func testStreamDeliversOutputThenExit() async throws {
        let messages = Messages()
        let refusal = gate().stream(RunRequest(command: "sh", arguments: ["-c", "echo a; echo b >&2; echo c"]), id: 7, grant: grant, emit: messages.add)
        XCTAssertNil(refusal)
        let finished = await waitUntil(5) { messages.exit != nil }
        XCTAssertTrue(finished)
        XCTAssertEqual(messages.output(.stdout), "a\nc\n")
        XCTAssertEqual(messages.output(.stderr), "b\n")
        guard case .runExit(7, let exit) = messages.all.last else { return XCTFail("exit was not last") }
        XCTAssertEqual(exit.status, 0)
        XCTAssertNil(exit.reason)
    }

    func testCancelAndConcurrencyLimit() async throws {
        var limits = CommandRunGate.Limits()
        limits.maxConcurrent = 1
        let gate = gate(limits)
        let messages = Messages()
        XCTAssertNil(gate.stream(RunRequest(command: "sleep", arguments: ["30"]), id: 1, grant: grant, emit: messages.add))
        XCTAssertEqual(gate.activeRuns(pluginID: grant.pluginID), 1)
        let busy = gate.stream(RunRequest(command: "sleep", arguments: ["30"]), id: 2, grant: grant, emit: messages.add)
        XCTAssertEqual(busy?.kind, .busy)

        let started = Date()
        XCTAssertTrue(gate.cancel(pluginID: grant.pluginID, id: 1))
        let stopped = await waitUntil(5) { messages.exit != nil }
        XCTAssertTrue(stopped)
        XCTAssertLessThan(Date().timeIntervalSince(started), 4)
        XCTAssertEqual(messages.exit?.reason, "cancelled")
        XCTAssertEqual(gate.activeRuns(pluginID: grant.pluginID), 0)
        XCTAssertEqual(gate.recentRuns(pluginID: grant.pluginID).first?.cancelled, true)
        XCTAssertFalse(gate.cancel(pluginID: grant.pluginID, id: 1))
    }

    func testReleasingAPluginStopsItsRuns() async throws {
        let messages = Messages()
        let services = HostServices.local(directory: root, platform: .init(system: SimulatedSystem()))
        let manifest = Manifest(id: "dev.test.run", name: "Run", capabilities: [.run(commands: ["sleep"])])
        let started = await services.handle(.run(RunRequest(command: "sleep", arguments: ["30"], stream: true)), for: manifest, id: 4, emit: messages.add)
        XCTAssertEqual(started, .ok)
        services.release(pluginID: manifest.id)
        let stopped = await waitUntil(5) { messages.exit != nil }
        XCTAssertTrue(stopped)
    }
}

final class RunAndContextServicesTests: XCTestCase {
    private func services(system: SimulatedSystem = SimulatedSystem(), approvalNeeded: @escaping @Sendable (String) -> Void = { _ in }, approved: (@Sendable (String) -> [String: String])? = nil) -> HostServices {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return HostServices(
            storage: StorageStore(directory: directory.appendingPathComponent("storage")),
            secrets: FileSecretStore(file: directory.appendingPathComponent("secrets.json")),
            platform: .init(system: system, approvalNeeded: approvalNeeded),
            runs: CommandRunGate(root: directory.appendingPathComponent("run")),
            approvedCommands: approved
        )
    }

    func testRunNeedsTheCommandDeclaredAndApproved() async throws {
        let services = services()
        let bare = Manifest(id: "dev.test.run", name: "Run")
        let declared = Manifest(id: "dev.test.run", name: "Run", capabilities: [.run(commands: ["echo"])])

        guard case .failure(let undeclared) = await services.handle(.run(RunRequest(command: "echo")), for: bare) else { return XCTFail("ran undeclared") }
        XCTAssertTrue(undeclared.contains(#".run(commands: ["echo"])"#), undeclared)
        guard case .failure(let waiting) = await services.handle(.run(RunRequest(command: "echo")), for: bare, declared: declared) else { return XCTFail("ran unapproved") }
        XCTAssertTrue(waiting.contains("approval"), waiting)
        guard case .failure(let other) = await services.handle(.run(RunRequest(command: "sh")), for: declared) else { return XCTFail("ran sh") }
        XCTAssertTrue(other.contains("not declared"), other)

        guard case .value(let json?) = await services.handle(.run(RunRequest(command: "echo", arguments: ["hi"])), for: declared) else { return XCTFail("did not run") }
        XCTAssertEqual(try SystemCodec.decode(RunResult.self, from: json).text, "hi\n")
        guard case .failure(let noStream) = await services.handle(.run(RunRequest(command: "echo", stream: true)), for: declared) else { return XCTFail("streamed without a channel") }
        XCTAssertTrue(noStream.contains("stream"))
    }

    func testAMovedCommandAsksForApprovalAgain() async {
        let asked = Copies()
        let services = services(approvalNeeded: { asked.add($0) }, approved: { _ in ["echo": "/old/place/echo"] })
        let manifest = Manifest(id: "dev.test.run", name: "Run", capabilities: [.run(commands: ["echo"])])
        guard case .failure(let message) = await services.handle(.run(RunRequest(command: "echo")), for: manifest) else { return XCTFail("ran a moved command") }
        XCTAssertTrue(message.contains("moved"), message)
        XCTAssertEqual(asked.all, ["dev.test.run"])
    }

    func testContextNeedsTheCapability() async throws {
        let system = SimulatedSystem()
        system.simulate(context: InvocationContext(frontmostApp: .init(bundleID: "com.apple.dt.Xcode", name: "Xcode"), windowTitle: "Package.swift", selectedText: String(repeating: "é", count: 60_000), finderSelection: ["/tmp/a.txt"]))
        let services = services(system: system)
        let bare = Manifest(id: "dev.test.context", name: "Context")
        let granted = Manifest(id: "dev.test.context", name: "Context", capabilities: [.context])

        guard case .failure(let message) = await services.handle(.context, for: bare) else { return XCTFail("read context without .context") }
        XCTAssertTrue(message.contains(".context"))
        guard case .failure = await services.handle(.finderSelection, for: bare) else { return XCTFail("read Finder without .context") }

        guard case .value(let json?) = await services.handle(.context, for: granted) else { return XCTFail("no context") }
        let context = try SystemCodec.decode(InvocationContext.self, from: json)
        XCTAssertEqual(context.frontmostApp?.name, "Xcode")
        XCTAssertEqual(context.windowTitle, "Package.swift")
        XCTAssertLessThanOrEqual(context.selectedText?.utf8.count ?? 0, InvocationContext.maxSelectedText)
        XCTAssertEqual(context.selectedText?.count, InvocationContext.maxSelectedText / 2)
        guard case .value(let files?) = await services.handle(.finderSelection, for: granted) else { return XCTFail("no Finder selection") }
        XCTAssertEqual(try SystemCodec.decode([String].self, from: files), ["/tmp/a.txt"])
    }
}

final class RunOnARealPluginTests: XCTestCase {
    private func start(granted: [Capability]? = nil) async throws -> (CommandRunner, PluginSupervisor, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore([:]))
        let registry = CommandRegistry(file: nil)
        let executable = PluginSupervisorTests.helper("FixturePlugin")
        let manifest = try PluginProcess.readManifest(executable: executable)
        let supervisor = PluginSupervisor(executable: executable, manifest: manifest, grantedCapabilities: granted, services: services) { update in
            if case .commands(let specs) = update { registry.update(pluginID: "fixture", pluginName: "Fixture", specs: specs) }
        }
        let runner = CommandRunner(registry: registry, services: services, timeout: 10) { id in id == "fixture" ? .supervisor(supervisor) : nil }
        await supervisor.start()
        let listed = await waitUntil { registry.entries.count == 8 }
        XCTAssertTrue(listed)
        return (runner, supervisor, directory)
    }

    func testAPluginRunsAndStreamsDeclaredCommands() async throws {
        let (runner, supervisor, directory) = try await start()
        defer { try? FileManager.default.removeItem(at: directory) }
        var outcome = await runner.run(CommandKey(pluginID: "fixture", commandID: "shell"), arguments: ["text": "hello there"], source: .palette)
        XCTAssertEqual(outcome.message, "ran: hello there (0)")
        outcome = await runner.run(CommandKey(pluginID: "fixture", commandID: "stream"), source: .palette)
        XCTAssertEqual(outcome.message?.hasPrefix("streamed "), true, "\(outcome)")
        XCTAssertEqual(Set(outcome.message?.dropFirst("streamed ".count).split(separator: " ").first?.split(separator: ",").map(String.init) ?? []), ["one", "two", "three"])
        XCTAssertEqual(outcome.message?.hasSuffix("exit 0"), true)

        let context = InvocationContext(frontmostApp: .init(bundleID: "com.apple.dt.Xcode", name: "Xcode"), selectedText: "let x = 1")
        outcome = await runner.run(CommandKey(pluginID: "fixture", commandID: "selection"), source: .hotkey, context: context)
        XCTAssertEqual(outcome.message, "selected let x = 1 in Xcode")
        await supervisor.stop()
    }

    func testWithoutTheCapabilitiesNothingRunsAndNoContextArrives() async throws {
        let (runner, supervisor, directory) = try await start(granted: [.secret(name: "FIXTURE_SECRET")])
        defer { try? FileManager.default.removeItem(at: directory) }
        var outcome = await runner.run(CommandKey(pluginID: "fixture", commandID: "shell"), source: .palette)
        XCTAssertTrue(outcome.isError)
        XCTAssertTrue(outcome.message?.contains("approval") == true, "\(outcome)")
        outcome = await runner.run(CommandKey(pluginID: "fixture", commandID: "selection"), source: .hotkey, context: InvocationContext(selectedText: "secret"))
        XCTAssertEqual(outcome.message, "selected nothing in nowhere")
        await supervisor.stop()
    }
}
