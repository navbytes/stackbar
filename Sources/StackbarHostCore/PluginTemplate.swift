import Foundation

/// The starting point for a new plugin: small, valid, and showing the shape
/// of everything (state, refresh, both surfaces, an action, a tool).
public enum PluginTemplate {
    public static func source(name: String, id: String? = nil) -> String {
        let typeName = typeName(for: name)
        let pluginID = id ?? "dev.local." + typeName.lowercased()
        return """
        import StackbarKit
        import Foundation

        /// \(name): describe what it shows in one sentence.
        @main
        final class \(typeName): StackbarPlugin {
            static let manifest = Manifest(
                id: "\(pluginID)",
                name: "\(name.replacingOccurrences(of: "\"", with: "'"))",
                summary: "What this plugin shows.",
                surfaces: [.menuBar, .panel],
                triggers: [.launch, .minutes(5)]
            )

            @Stored("count") var count = 0
            var updatedAt = Date()

            func refresh() async throws {
                updatedAt = Date()
            }

            var menuBar: ViewContent {
                Label("\\(count)", symbol: "sparkles")
            }

            var panel: ViewContent {
                Text("\(name.replacingOccurrences(of: "\"", with: "'"))").style(.headline)
                LabeledContent("Updated", value: updatedAt.formatted(date: .omitted, time: .shortened))
                Button("Add one", symbol: "plus") { self.count += 1 }
            }

            var tools: [AgentTool] {
                AgentTool("count", description: "The current count") { _ in "\\(self.count)" }
            }
        }

        """
    }

    /// A Swift type name from a display name: "My PR list" → "MyPRList".
    public static func typeName(for name: String) -> String {
        let words = name.split { !$0.isLetter && !$0.isNumber }
        var result = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        if result.isEmpty { result = "Plugin" }
        if result.first!.isNumber { result = "Plugin" + result }
        return result
    }
}
