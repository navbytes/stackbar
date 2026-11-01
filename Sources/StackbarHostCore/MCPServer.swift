import Foundation
import StackbarProtocol

/// A Model Context Protocol server: JSON-RPC 2.0, one message per line.
///
/// Stackbar runs two: the authoring server (`stackbarctl mcp`) for an agent writing
/// a plugin, and the runtime gateway (`stackbarctl agent`) that exposes running
/// plugins' tools. Both are this server with a different `MCPToolProvider`.
/// Only tools are offered; resources and prompts aren't needed yet.
public actor MCPServer {
    public static let protocolVersion = "2025-06-18"

    public let name: String
    public let version: String
    public let instructions: String?
    private let provider: any MCPToolProvider

    public init(name: String, version: String, instructions: String? = nil, provider: any MCPToolProvider) {
        self.name = name
        self.version = version
        self.instructions = instructions
        self.provider = provider
    }

    /// Handles one line; returns the line to write back, if any.
    public func handle(line: Data) async -> Data? {
        guard let request = try? JSONDecoder().decode(Request.self, from: line) else {
            return encode(Response(id: .null, error: RPCError(code: -32700, message: "parse error")))
        }
        guard let id = request.id else {
            return nil // a notification: initialized, cancelled, ...
        }
        do {
            return encode(Response(id: id, result: try await result(for: request)))
        } catch let error as RPCError {
            return encode(Response(id: id, error: error))
        } catch {
            return encode(Response(id: id, error: RPCError(code: -32603, message: "\(error)")))
        }
    }

    private func result(for request: Request) async throws -> JSONValue {
        switch request.method {
        case "initialize":
            let requested = request.params?["protocolVersion"]?.string
            var result: [String: JSONValue] = [
                "protocolVersion": .string(requested ?? Self.protocolVersion),
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": .string(name), "version": .string(version)],
            ]
            if let instructions { result["instructions"] = .string(instructions) }
            return .object(result)
        case "ping":
            return [:]
        case "tools/list":
            return ["tools": .array(await provider.tools().map(\.json))]
        case "tools/call":
            guard let name = request.params?["name"]?.string else { throw RPCError(code: -32602, message: "tools/call needs a name") }
            let arguments = request.params?["arguments"]?.object ?? [:]
            return await provider.call(name, arguments: arguments).json
        default:
            throw RPCError(code: -32601, message: "method not found: \(request.method)")
        }
    }

    /// Serves stdin/stdout until stdin closes.
    public func serveStdio() async {
        let input = FileHandle.standardInput
        let output = FileHandle.standardOutput
        let lines = AsyncStream<Data> { continuation in
            Thread {
                var buffer = LineBuffer()
                while withAutoreleasePool({ () -> Bool in
                    let chunk = input.availableData
                    if chunk.isEmpty { return false }
                    for line in buffer.append(chunk) { continuation.yield(line) }
                    return true
                }) {}
                continuation.finish()
            }.start()
        }
        for await line in lines {
            if let reply = await handle(line: line) { output.write(reply) }
        }
    }

    private func encode(_ response: Response) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        var data = (try? encoder.encode(response)) ?? Data()
        data.append(0x0A)
        return data
    }

    struct Request: Decodable {
        var id: JSONValue?
        var method: String
        var params: JSONValue?
    }

    struct Response: Encodable {
        var jsonrpc = "2.0"
        var id: JSONValue
        var result: JSONValue?
        var error: RPCError?

        init(id: JSONValue, result: JSONValue) {
            self.id = id
            self.result = result
        }

        init(id: JSONValue, error: RPCError) {
            self.id = id
            self.error = error
        }
    }

    struct RPCError: Error, Encodable {
        var code: Int
        var message: String
    }
}

/// What an MCP server offers.
public protocol MCPToolProvider: Sendable {
    func tools() async -> [MCPTool]
    func call(_ name: String, arguments: [String: JSONValue]) async -> MCPToolResult
}

public struct MCPTool: Sendable, Equatable {
    public var name: String
    public var description: String
    public var inputSchema: JSONValue

    public init(name: String, description: String, properties: [String: JSONValue] = [:], required: [String] = []) {
        self.name = name
        self.description = description
        self.inputSchema = ["type": "object", "properties": .object(properties), "required": .array(required.map { .string($0) })]
    }

    var json: JSONValue {
        ["name": .string(name), "description": .string(description), "inputSchema": inputSchema]
    }

    public static func property(_ type: String, _ description: String, enumValues: [String]? = nil) -> JSONValue {
        var object: [String: JSONValue] = ["type": .string(type), "description": .string(description)]
        if let enumValues { object["enum"] = .array(enumValues.map { .string($0) }) }
        return .object(object)
    }
}

public struct MCPToolResult: Sendable, Equatable {
    public enum Content: Sendable, Equatable {
        case text(String)
        case image(Data, mimeType: String)
    }

    public var content: [Content]
    public var isError: Bool

    public init(_ content: [Content], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }

    public static func text(_ text: String, isError: Bool = false) -> MCPToolResult { MCPToolResult([.text(text)], isError: isError) }

    var json: JSONValue {
        let items: [JSONValue] = content.map { item in
            switch item {
            case .text(let text): return ["type": "text", "text": .string(text)]
            case .image(let data, let mimeType): return ["type": "image", "data": .string(data.base64EncodedString()), "mimeType": .string(mimeType)]
            }
        }
        return ["content": .array(items), "isError": .bool(isError)]
    }
}
