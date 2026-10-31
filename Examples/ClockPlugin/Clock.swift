import StackbarKit
import Foundation

/// The smallest useful Stackbar plugin: a menu-bar clock with a panel that shows
/// state, a toggle and a button. Needs no network and no secrets; its settings
/// and laps are `@Stored`, so they survive restarts.
@main
final class Clock: StackbarPlugin {
    static let manifest = Manifest(
        id: "io.navbytes.stackbar.example.clock",
        name: "Clock",
        surfaces: [.menuBar, .panel],
        triggers: [.launch, .every(.seconds(1))]
    )

    var now = Date()
    @Stored("use24Hour") var use24Hour = true
    @Stored("laps") var laps: [Date] = []

    func refresh() async throws {
        now = Date()
    }

    var menuBar: ViewContent {
        Label(time(now), symbol: "clock")
    }

    var panel: ViewContent {
        VStack(spacing: 8) {
            Text(time(now)).style(.title)
            Text(now.formatted(date: .complete, time: .omitted)).role(.secondary)
            ProgressBar("Day", value: dayProgress)
            Toggle("24-hour clock", isOn: use24Hour) { self.use24Hour = $0 }
            Divider()
            Button("Lap", symbol: "flag") { self.laps.insert(Date(), at: 0) }
            if !laps.isEmpty {
                List {
                    ForEach(laps.prefix(5).enumerated()) { index, lap in
                        Row("Lap \(laps.count - index)", subtitle: time(lap), symbol: "flag.checkered", key: "lap-\(lap.timeIntervalSince1970)")
                    }
                }
                Button("Clear laps", role: .critical) { self.laps.removeAll() }
            }
        }
    }

    private var dayProgress: Double {
        let start = Calendar.current.startOfDay(for: now)
        return now.timeIntervalSince(start) / 86_400
    }

    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = use24Hour ? "HH:mm:ss" : "h:mm:ss a"
        return formatter.string(from: date)
    }
}
