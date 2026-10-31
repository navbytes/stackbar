import FluidKit
import Foundation

/// A small to-do list kept by the host. It hides finished items while you're
/// in a Pomodoro focus session (it listens on `focus.state`), and agents can
/// add to it.
@main
final class Todo: FluidPlugin {
    static let manifest = Manifest(
        id: "dev.fluid.example.todo",
        name: "To-do",
        summary: "A to-do list that agents can add to.",
        surfaces: [.menuBar, .panel, .window, .widget],
        triggers: [.launch, .topic(name: "focus.state")]
    )

    struct Item: Codable, Equatable {
        var id: String
        var title: String
        var done: Bool
    }

    @Stored("items") var items: [Item] = []
    var focusing = false

    private var open: [Item] { items.filter { !$0.done } }

    func receive(topic: String, payload: String, from sender: String) async throws {
        focusing = payload == "focus"
    }

    var menuBar: ViewContent {
        Label(open.isEmpty ? "" : "\(open.count)", symbol: open.isEmpty ? "checklist.checked" : "checklist")
    }

    var panel: ViewContent {
        TextField("Add a to-do") { title in self.add(title) }
        if items.isEmpty {
            ContentUnavailableView("Nothing to do", symbol: "checkmark.circle")
        } else {
            List(focusing ? open : items, searchable: items.count > 8) { item in
                Row(item.title, symbol: item.done ? "checkmark.circle.fill" : "circle", key: item.id)
                    .action(item.done ? "Mark as not done" : "Mark as done") { self.toggle(item.id) }
                    .action("Delete", role: .critical) { self.items.removeAll { $0.id == item.id } }
            }
            if items.contains(where: \.done) && !focusing {
                Button("Clear finished") { self.items.removeAll(where: \.done) }
            }
        }
        if focusing { Text("Focus mode: finished items are hidden").style(.caption).role(.secondary) }
    }

    var tools: [AgentTool] {
        AgentTool("list", description: "My open to-dos, one per line") { _ in
            self.open.isEmpty ? "Nothing open." : self.open.map { "- \($0.title)" }.joined(separator: "\n")
        }
        AgentTool("add", description: "Add a to-do", parameters: [ToolParameter("title", description: "What to do")]) { arguments in
            guard let title = arguments.string("title") else { return "missing title" }
            self.add(title)
            return "Added \"\(title)\""
        }
    }

    private func add(_ title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        items.insert(Item(id: UUID().uuidString, title: title, done: false), at: 0)
    }

    private func toggle(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].done.toggle()
    }
}
