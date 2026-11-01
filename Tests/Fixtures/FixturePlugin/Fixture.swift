import StackbarKit
import Foundation

/// A test plugin that misbehaves on request: its buttons crash the process or
/// print to stdout, so the supervisor and the stdio guard are tested against a
/// real process. It also exercises every host service.
@main
final class Fixture: StackbarPlugin {
    static let manifest = Manifest(
        id: "io.navbytes.stackbar.test.fixture",
        name: "Fixture",
        triggers: [.launch, .topic(name: "fixture.inbox")],
        capabilities: [.secret(name: "FIXTURE_SECRET"), .network("127.0.0.1"), .run(commands: ["echo", "sh"]), .context]
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
        Button("Secret") { self.status = "secret " + ((try await Stackbar.secret("FIXTURE_SECRET")) ?? "missing") }
        Button("Undeclared secret") {
            do {
                _ = try await Stackbar.secret("OTHER")
                self.status = "leaked"
            } catch {
                self.status = "refused"
            }
        }
        TextField("URL") { url in
            do {
                let response = try await Stackbar.get(url)
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

    var commands: [Command] {
        Command("bump", title: "Bump Count") { invocation in
            self.count += Int(invocation["by"] ?? "1") ?? 1
            return .message("count \(self.count)")
        }
        .argument("by", required: false, default: "1")
        Command("copy-count", title: "Copy Count") { _ in .copy("\(self.count)") }
        Command("slow", title: "Slow") { _ in
            try await Task.sleep(for: .seconds(5))
            return .done
        }
        Command("inside", title: "Inside Only") { _ in .done }
            .stackbarOnly()
        Command("echo", title: "Echo")
            .view { invocation in Text("query \(invocation.text)") }
        Command("shell", title: "Run Echo") { invocation in
            let result = try await Stackbar.run("echo", [invocation["text"] ?? "hi"])
            return .message("ran: \(result.text.trimmingCharacters(in: .newlines)) (\(result.status))")
        }
        .argument("text", required: false)
        Command("stream", title: "Stream Shell") { _ in
            var lines: [String] = []
            var status: Int32 = -1
            for try await event in Stackbar.stream("sh", ["-c", "echo one; echo two >&2; echo three"]) {
                switch event {
                // A chunk can hold several lines, or part of one.
                case .stdout(let data), .stderr(let data): lines += String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
                case .exit(let exit): status = exit.status
                }
            }
            return .message("streamed \(lines.joined(separator: ",")) exit \(status)")
        }
        Command("selection", title: "Selection") { invocation in
            .message("selected \(invocation.context?.selectedText ?? "nothing") in \(invocation.context?.frontmostApp?.name ?? "nowhere")")
        }
    }

    func receive(topic: String, payload: String, from sender: String) async throws {
        status = "topic \(topic) \(payload) from \(sender)"
    }
}
