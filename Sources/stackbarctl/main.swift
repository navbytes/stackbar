import Foundation
import StackbarHostCore
import StackbarProtocol

// stackbarctl — build, inspect and drive Stackbar plugins without the app, and serve
// them to agents over MCP.
//
// This file reads the command and hands it on. Each command is a function in
// one of the *Commands files (or Render.swift), on the main actor like the
// code here; Support.swift has what they share and Usage.swift the help.

let arguments = CommandLine.arguments.dropFirst().filter { $0 != "--no-sandbox" && $0 != "--real-storage" }
guard let command = arguments.first else { fail(usage) }
let rest = Array(arguments.dropFirst())

switch command {
case "docs": print(AuthoringGuide.text)
case "parity": print(SurfaceParity.ledger())
case "version", "--version": print("stackbarctl \(StackbarVersion.current), protocol \(StackbarProtocolVersion.current)")
case "new": newPlugin(rest)
case "build": build(rest)
case "manifest": manifest(rest)
case "previews": listPreviews(rest)
case "commands", "run": await commands(rest, run: command == "run")
case "render":
    guard let path = rest.first else { fail(usage) }
    await render(path, options: Array(rest.dropFirst()))
case "soak": await soak(rest)
case "mcp": await serveAuthoring()
case "agent": await serveAgent(rest)
case "call": call(rest)
case "helper": prebuiltHelper(rest)
case "keygen": keygen(rest)
case "sign": sign(rest)
case "verify": verify(rest)
case "install": await install(rest)
case "index": await index(rest)
case "logs": logs(rest)
case "doctor": doctor()
case "settings": settings(rest)
case "secret": secret(rest)
default: fail(usage)
}
