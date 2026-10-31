import StackbarKit
import Foundation

/// A focus timer in the menu bar. It tells other plugins when a focus session
/// starts and ends (topic `focus.state`), and keeps today's count.
@main
final class Pomodoro: StackbarPlugin {
    static let manifest = Manifest(
        id: "io.navbytes.stackbar.example.pomodoro",
        name: "Pomodoro",
        summary: "A focus timer that tells other plugins when you're focusing.",
        surfaces: [.menuBar, .panel, .widget],
        triggers: [.launch, .every(.seconds(1))]
    )

    enum Phase: String, Codable { case idle, focus, rest }

    @Stored("focusMinutes") var focusMinutes = 25.0
    @Stored("restMinutes") var restMinutes = 5.0
    @Stored("completed") var completed: [String: Int] = [:]
    var phase = Phase.idle
    var endsAt: Date?

    private var today: String { ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate]) }
    private var remaining: TimeInterval { max(0, endsAt?.timeIntervalSinceNow ?? 0) }

    func refresh() async throws {
        guard phase != .idle, remaining == 0 else { return }
        if phase == .focus {
            completed[today, default: 0] += 1
            Stackbar.notify("Focus session done", body: "Take \(Int(restMinutes)) minutes.")
            start(.rest)
        } else {
            Stackbar.notify("Break's over")
            stop()
        }
    }

    var menuBar: ViewContent {
        switch phase {
        case .idle: Label("", symbol: "timer")
        case .focus: Label(clock(remaining), symbol: "brain.head.profile").role(.accent)
        case .rest: Label(clock(remaining), symbol: "cup.and.saucer").role(.success)
        }
    }

    var panel: ViewContent {
        Text(phase == .idle ? "Ready to focus" : phase == .focus ? "Focusing" : "On a break").style(.headline)
        if phase != .idle {
            let total = (phase == .focus ? focusMinutes : restMinutes) * 60
            ProgressBar(clock(remaining), value: total - remaining, total: total, role: phase == .focus ? .accent : .success)
            Button("Stop", symbol: "stop.fill", role: .critical) { self.stop() }
        } else {
            Button("Start focus", symbol: "play.fill") { self.start(.focus) }
        }
        LabeledContent("Today", value: "\(completed[today] ?? 0) sessions")
        Slider("Focus minutes: \(Int(focusMinutes))", value: focusMinutes, in: 5...90, step: 5) { self.focusMinutes = $0 }
        Slider("Break minutes: \(Int(restMinutes))", value: restMinutes, in: 1...30, step: 1) { self.restMinutes = $0 }
    }

    var widget: ViewContent {
        Label(phase == .idle ? "Idle" : clock(remaining), symbol: "timer")
        LabeledContent("Today", value: "\(completed[today] ?? 0)")
    }

    var tools: [AgentTool] {
        AgentTool("status", description: "Whether I'm focusing, and how long is left") { _ in
            self.phase == .idle ? "Not focusing. \(self.completed[self.today] ?? 0) sessions today." : "\(self.phase.rawValue), \(self.clock(self.remaining)) left"
        }
        AgentTool("start_focus", description: "Start a focus session") { _ in
            self.start(.focus)
            return "Focusing for \(Int(self.focusMinutes)) minutes"
        }
    }

    private func start(_ next: Phase) {
        phase = next
        endsAt = Date().addingTimeInterval((next == .focus ? focusMinutes : restMinutes) * 60)
        Stackbar.publish("focus.state", next.rawValue)
    }

    private func stop() {
        phase = .idle
        endsAt = nil
        Stackbar.publish("focus.state", Phase.idle.rawValue)
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
