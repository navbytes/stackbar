#if os(macOS)
import AppKit
import Darwin
import StackbarHostCore

/// `STACKBAR_BENCHMARK=<file.json>`: Stackbar times itself and quits. The
/// Benchmark workflow runs it on a clean macOS runner; the numbers it writes
/// are the ones the site quotes.
///
/// - launch: process start to the end of `applicationDidFinishLaunching`
/// - plugins ready: process start until every plugin is running
/// - palette open: the hotkey's work until the panel is on screen, laid out
/// - search: typing a query until a plugin's answer is in the results
/// - memory: the app's footprint (what Activity Monitor shows) after idling,
///   not counting plugins, which run as their own processes
@MainActor
enum Benchmark {
    static var output: URL? {
        ProcessInfo.processInfo.environment["STACKBAR_BENCHMARK"].map { URL(fileURLWithPath: $0) }
    }

    static func run(app: AppDelegate, launched: Date) {
        guard let output else { return }
        Task { @MainActor in
            var report: [String: Any] = [
                "version": StackbarVersion.current,
                "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
                "launchMs": ms(launched.timeIntervalSince(processStart)),
            ]
            let ready = await waitUntil(seconds: 60) { !app.model.controllers.isEmpty && app.model.controllers.allSatisfy(\.isSettled) }
            report["plugins"] = app.model.controllers.map(\.name).sorted()
            report["pluginsReadyMs"] = ready ? ms(Date().timeIntervalSince(processStart)) : NSNull()
            // A fresh home has nothing approved yet. Approve what the core
            // plugins ask for, as a user does once, so search can answer.
            for controller in app.model.controllers where controller.isWaitingForApproval {
                controller.approve()
            }
            _ = await waitUntil(seconds: 30) { app.model.controllers.allSatisfy { !$0.isWaitingForApproval && $0.isSettled } }
            try? await Task.sleep(for: .seconds(2))

            var opens: [Double] = []
            for _ in 0..<10 {
                let start = Date()
                app.palette.toggle()
                _ = await waitUntil(seconds: 5) { app.palette.isVisible }
                await nextFrame()
                opens.append(ms(Date().timeIntervalSince(start)))
                app.palette.hide()
                try? await Task.sleep(for: .milliseconds(300))
            }
            report["paletteOpenMs"] = summary(opens)

            var searches: [String: Any] = [:]
            var misses: [String: [String]] = [:]
            for (query, expected) in [("calendar", "Calendar"), ("12*12", "144"), ("terminal", "Terminal")] {
                app.palette.toggle()
                _ = await waitUntil(seconds: 5) { app.palette.isVisible }
                let start = Date()
                app.palette.session.query = query
                let found = await waitUntil(seconds: 5) {
                    app.palette.session.results.contains { $0.title.contains(expected) || ($0.subtitle ?? "").contains(expected) }
                }
                searches[query] = found ? ms(Date().timeIntervalSince(start)) : NSNull()
                if !found {
                    // What the palette showed instead, to see why.
                    misses[query] = missDetail(app)
                }
                app.palette.hide()
                try? await Task.sleep(for: .milliseconds(300))
            }
            report["searchMs"] = searches
            if !misses.isEmpty { report["searchMisses"] = misses }

            try? await Task.sleep(for: .seconds(20))
            report["idleMemoryMB"] = footprintMB()

            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: output, options: .atomic)
            }
            NSApp.terminate(nil)
        }
    }

    /// What the palette and the command registry held when a search missed.
    private static func missDetail(_ app: AppDelegate) -> [String] {
        var lines: [String] = []
        for section in app.palette.session.sections {
            let titles = section.entries.prefix(3).map(\.title)
            lines.append(section.title + ": " + titles.joined(separator: ", "))
        }
        lines.append("root views revision \(app.palette.session.rootViewsRevision)")
        let commands: CommandCenter = app.model.commands
        for entry in commands.registry.entries {
            let preference: CommandPreference = commands.preferences[entry.key]
            let line: String = "command \(entry.key) root=\(entry.spec.rootSearch) enabled=\(preference.enabled) inRoot=\(preference.inRootSearch.map(String.init) ?? "default")"
            lines.append(line)
        }
        for controller in app.model.controllers {
            let line: String = "plugin \(controller.name) \(controller.state) waiting=\(controller.isWaitingForApproval) supervisor=\(controller.supervisor != nil)"
            lines.append(line)
        }
        return lines
    }

    private static func ms(_ seconds: TimeInterval) -> Double { (seconds * 10_000).rounded() / 10 }

    private static func summary(_ values: [Double]) -> [String: Double] {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return [:] }
        return ["median": sorted[sorted.count / 2], "min": sorted[0], "max": sorted[sorted.count - 1]]
    }

    /// Polls every 10 ms on the main actor.
    private static func waitUntil(seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// After AppKit has drawn: the next pass of the run loop.
    private static func nextFrame() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    /// When this process started, from the kernel.
    private static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return Date() }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
    }()

    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return (Double(info.phys_footprint) / 1_048_576 * 10).rounded() / 10
    }
}
extension PluginController {
    /// Done starting, one way or the other.
    var isSettled: Bool {
        switch state {
        case .running, .failed: return true
        case .stopped, .starting, .restarting: return false
        }
    }

    var hasFailed: Bool {
        if case .failed = state { return true }
        return false
    }
}
#endif
