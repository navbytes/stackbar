import AppIntents
import SwiftUI
import WidgetKit
import StackbarHostCore
import StackbarProtocol
import StackbarUI

// The Stackbar widget: shows one plugin's `widget` surface from the snapshot the
// app writes to the shared app group. Built by the Xcode project (project.yml),
// not by SwiftPM, because widget extensions need an app bundle around them.

struct PluginEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Plugin"
    static let defaultQuery = PluginQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct PluginQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PluginEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [PluginEntity] {
        WidgetSnapshotStore.shared().all().map { PluginEntity(id: $0.pluginID, name: $0.name) }
    }
}

struct SelectPlugin: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Plugin"
    static let description = IntentDescription("Which Stackbar plugin to show.")

    @Parameter(title: "Plugin")
    var plugin: PluginEntity?
}

struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot?
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: WidgetSnapshot(pluginID: "placeholder", name: "Stackbar", node: .label("Stackbar", symbol: "drop")))
    }

    func snapshot(for configuration: SelectPlugin, in context: Context) async -> SnapshotEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectPlugin, in context: Context) async -> Timeline<SnapshotEntry> {
        // The app reloads timelines whenever a plugin's widget tree changes;
        // the 15-minute policy is only a fallback.
        Timeline(entries: [entry(for: configuration)], policy: .after(Date().addingTimeInterval(15 * 60)))
    }

    private func entry(for configuration: SelectPlugin) -> SnapshotEntry {
        let store = WidgetSnapshotStore.shared()
        let snapshot = configuration.plugin.flatMap { store.read($0.id) } ?? store.all().first
        return SnapshotEntry(date: Date(), snapshot: snapshot)
    }
}

struct StackbarWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            WidgetContentView(node: snapshot.node)
                .containerBackground(.fill.tertiary, for: .widget)
        } else {
            ContentUnavailableView("No plugin", systemImage: "drop", description: Text("Open Stackbar and add a plugin with a widget."))
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

@main
struct StackbarWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "io.navbytes.stackbar.widget", intent: SelectPlugin.self, provider: Provider()) { entry in
            StackbarWidgetView(entry: entry)
        }
        .configurationDisplayName("Stackbar Plugin")
        .description("Shows a Stackbar plugin's widget.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
