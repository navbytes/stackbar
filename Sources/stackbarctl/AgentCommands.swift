import Foundation
import StackbarHostCore
import StackbarProtocol

// The commands that serve plugins to agents, or reach the running app.

/// `mcp`: the authoring tools over MCP on stdio.
@MainActor
func serveAuthoring() async {
    let tools = AuthoringTools(loader: loader, services: makeServices(), png: pngRenderer())
    let server = MCPServer(name: "stackbar-authoring", version: StackbarVersion.current, instructions: "Tools for writing Stackbar plugins: call stackbar_docs first, then stackbar_new/stackbar_build/stackbar_render/stackbar_send_event.", provider: tools)
    await server.serveStdio()
    await tools.stopAll()
}

/// `agent`: the running app's plugins over MCP, or the given plugins run here.
@MainActor
func serveAgent(_ rest: [String]) async {
    if rest.isEmpty {
        do {
            try UnixSocket.bridgeStdio(to: StackbarPaths.agentSocket.path)
        } catch {
            fail("\(error)\nStart Stackbar, or pass plugin files to run them here: stackbarctl agent <plugin.swift>...")
        }
    } else {
        let services = makeServices()
        var supervisors: [PluginSupervisor] = []
        for path in rest {
            let plugin = load(path)
            let supervisor = PluginSupervisor(executable: plugin.binary, manifest: plugin.manifest, services: services)
            await supervisor.start()
            supervisors.append(supervisor)
        }
        let running = supervisors
        let server = MCPServer(name: "stackbar", version: StackbarVersion.current, instructions: "Tools from running Stackbar plugins. Call stackbar_plugins to see them.", provider: RuntimeTools { running })
        await server.serveStdio()
        for supervisor in supervisors { await supervisor.stop() }
    }
}

/// `call`: runs a command in the running app.
@MainActor
func call(_ rest: [String]) {
    guard rest.count >= 2, !rest[0].hasPrefix("-"), !rest[1].hasPrefix("-") else { fail(usage) }
    guard let arguments = CommandCall.arguments(from: Array(rest.dropFirst(2))) else { fail("--arg takes name=value") }
    do {
        let call = CommandCall(plugin: rest[0], command: rest[1], arguments: arguments)
        let line = try UnixSocket.request(JSONEncoder().encode(call), to: StackbarPaths.commandSocket.path)
        guard let reply = try? JSONDecoder().decode(CommandCall.Reply.self, from: line) else { fail("Stackbar sent no answer") }
        if reply.isError { fail(reply.message ?? "failed") }
        print(reply.message ?? "Done")
    } catch {
        fail("Stackbar isn't running (\(error)). Open it, then try again.")
    }
}
