/// Something an agent can ask the plugin to do or tell it, exposed over MCP by
/// the host's agent gateway.
///
/// ```swift
/// var tools: [AgentTool] {
///     AgentTool("list_review_queue", description: "Pull requests waiting on my review") { _ in
///         pullRequests.map { "\($0.repo)#\($0.number) \($0.title)" }.joined(separator: "\n")
///     }
/// }
/// ```
///
/// Tools run on the plugin's main actor like everything else, so they see the
/// same state the panel shows. After a tool runs, the plugin re-renders.
public struct AgentTool: Sendable {
    public typealias Perform = @MainActor @Sendable ([String: EventValue]) async throws -> String

    public var spec: ToolSpec
    var perform: Perform

    public init(_ name: String, description: String, parameters: [ToolParameter] = [], perform: @escaping Perform) {
        self.spec = ToolSpec(name: name, description: description, parameters: parameters)
        self.perform = perform
    }
}

@resultBuilder
public enum ToolBuilder {
    public static func buildExpression(_ tool: AgentTool) -> [AgentTool] { [tool] }
    public static func buildBlock(_ parts: [AgentTool]...) -> [AgentTool] { parts.flatMap { $0 } }
    public static func buildOptional(_ part: [AgentTool]?) -> [AgentTool] { part ?? [] }
    public static func buildEither(first part: [AgentTool]) -> [AgentTool] { part }
    public static func buildEither(second part: [AgentTool]) -> [AgentTool] { part }
    public static func buildArray(_ parts: [[AgentTool]]) -> [AgentTool] { parts.flatMap { $0 } }
}

extension Dictionary where Key == String, Value == EventValue {
    public func string(_ key: String) -> String? {
        switch self[key] {
        case .text(let value)?: return value
        case .number(let value)?: return value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
        case .bool(let value)?: return String(value)
        case .fields?, nil: return nil
        }
    }

    public func number(_ key: String) -> Double? {
        switch self[key] {
        case .number(let value)?: return value
        case .text(let value)?: return Double(value)
        default: return nil
        }
    }

    public func bool(_ key: String) -> Bool? {
        switch self[key] {
        case .bool(let value)?: return value
        case .text(let value)?: return Bool(value)
        default: return nil
        }
    }
}
