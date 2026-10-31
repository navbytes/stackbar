import FluidKit
import Foundation

/// A test plugin that misbehaves on request: its buttons crash the process or
/// print to stdout, so the supervisor and the stdio guard are tested against a
/// real process. It also exercises every host service.
@main
final class Fixture: FluidPlugin {
    static let manifest = Manifest(
        id: "dev.fluid.test.fixture",
        name: "Fixture",
        triggers: [.launch, .topic(name: "fixture.inbox")],
        capabilities: [.secret(name: "FIXTURE_SECRET"), .network("127.0.0.1")]
    )

    var count = 0
    @Stored("saved") var saved = 0
    var status = "idle"

    var menuBar: ViewContent {
        Text("count \(count)")
    }

    var panel: ViewContent {
        Text("saved \(saved)")
        Text("status \(status)")
        Button("Increment") { self.count += 1 }
        Button("Save") { self.saved += 1 }
        Button("Print") {
            // Must land on stderr, not in the protocol stream.
            print("stray output from plugin code")
            self.count += 10
        }
        Button("Crash") { exit(3) }
        Button("Spawn") {
            // A grandchild the host must clean up when this plugin dies.
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/bin/sleep")
            child.arguments = ["300"]
            try child.run()
            self.status = "child \(child.processIdentifier)"
        }
        Button("Secret") { self.status = "secret " + ((try await Fluid.secret("FIXTURE_SECRET")) ?? "missing") }
        Button("Undeclared secret") {
            do {
                _ = try await Fluid.secret("OTHER")
                self.status = "leaked"
            } catch {
                self.status = "refused"
            }
        }
        TextField("URL") { url in
            do {
                let response = try await Fluid.get(url)
                self.status = "http \(response.status) \(String(decoding: response.body, as: UTF8.self))"
            } catch {
                self.status = "http error \(error)"
            }
        }
    }

    var tools: [AgentTool] {
        AgentTool("count", description: "The current count") { _ in "\(self.count)" }
        AgentTool("add", description: "Adds to the count", parameters: [ToolParameter("amount", .number)]) { arguments in
            self.count += Int(arguments.number("amount") ?? 0)
            return "now \(self.count)"
        }
    }

    func receive(topic: String, payload: String, from sender: String) async throws {
        status = "topic \(topic) \(payload) from \(sender)"
    }
}
