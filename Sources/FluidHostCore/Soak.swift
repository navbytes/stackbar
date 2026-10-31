import Foundation
import FluidProtocol
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Runs a plugin for a while under steady load and watches its memory: the
/// phase 0 "flat memory" gate, as a command anyone can run against any plugin.
///
/// Every tick it sends a manual refresh, hides and shows the panel, and (with
/// `pressEvents`) presses every button the panel offers except ones whose
/// label suggests they destroy state. Resident memory is sampled each tick.
public struct Soak: Sendable {
    public var duration: Double
    public var interval: Double
    public var pressEvents: Bool
    /// Growth allowed between the start and the end of the run, after warm-up.
    public var allowedGrowth: Double

    public init(duration: Double, interval: Double = 1, pressEvents: Bool = false, allowedGrowth: Double = 0.15) {
        self.duration = duration
        self.interval = interval
        self.pressEvents = pressEvents
        self.allowedGrowth = allowedGrowth
    }

    public struct Report: Sendable, CustomStringConvertible {
        public var samples: [Int]
        public var restarts: Int
        public var ticks: Int
        public var allowedGrowth: Double

        /// Median of the first and last fifth, skipping the first tenth as warm-up.
        public var baseline: Int { Self.median(window(first: true)) }
        public var final: Int { Self.median(window(first: false)) }
        public var growth: Double { baseline > 0 ? Double(final - baseline) / Double(baseline) : 0 }
        /// Small absolute changes (allocator noise) never fail the gate.
        public var isFlat: Bool { growth <= allowedGrowth || final - baseline < 2 * 1024 * 1024 }
        public var passed: Bool { isFlat && restarts == 0 && !samples.isEmpty }

        public var description: String {
            func mb(_ bytes: Int) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }
            let verdict = passed ? "PASS" : "FAIL"
            var lines = [
                "\(verdict): \(ticks) ticks, \(samples.count) samples, \(restarts) restarts",
                "resident memory \(mb(baseline)) → \(mb(final)) (\(String(format: "%+.1f%%", growth * 100)), allowed \(Int(allowedGrowth * 100))%)",
                "peak \(mb(samples.max() ?? 0))",
            ]
            if restarts > 0 { lines.append("the plugin crashed during the run") }
            if samples.isEmpty { lines.append("no memory samples: the helper never ran") }
            return lines.joined(separator: "\n")
        }

        private func window(first: Bool) -> [Int] {
            let usable = Array(samples.dropFirst(samples.count / 10))
            let width = max(1, usable.count / 5)
            return first ? Array(usable.prefix(width)) : Array(usable.suffix(width))
        }

        private static func median(_ values: [Int]) -> Int {
            guard !values.isEmpty else { return 0 }
            return values.sorted()[values.count / 2]
        }
    }

    public func run(_ supervisor: PluginSupervisor, progress: @Sendable (Int, Int) -> Void = { _, _ in }) async -> Report {
        await supervisor.start()
        _ = await waitForRunning(supervisor)
        var samples: [Int] = []
        var ticks = 0
        let end = Date().addingTimeInterval(duration)
        while Date() < end {
            ticks += 1
            await supervisor.send(.trigger(reason: .manual))
            await supervisor.send(.visibility(surface: .panel, visible: false))
            await supervisor.send(.visibility(surface: .panel, visible: true))
            if pressEvents, let panel = await supervisor.views[.panel] {
                for action in Self.safeActions(in: panel) { await supervisor.event(action) }
            }
            try? await Task.sleep(for: .seconds(interval))
            if let pid = await supervisor.helperPID, let bytes = ProcessMemory.residentBytes(pid) {
                samples.append(bytes)
                progress(ticks, bytes)
            }
        }
        let restarts = await supervisor.restarts
        await supervisor.stop()
        return Report(samples: samples, restarts: restarts, ticks: ticks, allowedGrowth: allowedGrowth)
    }

    /// Button actions, minus anything that sounds destructive or crashes.
    static func safeActions(in node: ViewNode) -> [ActionID] {
        let avoid = ["crash", "delete", "remove", "clear", "reset", "quit", "sign out", "logout", "uninstall"]
        return node.actions.filter { action in
            guard action.rawValue.hasPrefix("button/") else { return false }
            let label = action.rawValue.lowercased()
            return !avoid.contains { label.contains($0) }
        }
    }

    private func waitForRunning(_ supervisor: PluginSupervisor) async -> Bool {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if await supervisor.state == .running { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}

/// Resident memory of a process.
public enum ProcessMemory {
    public static func residentBytes(_ pid: Int32) -> Int? {
        #if os(Linux)
        guard let statm = try? String(contentsOfFile: "/proc/\(pid)/statm", encoding: .utf8) else { return nil }
        let fields = statm.split(separator: " ")
        guard fields.count > 1, let pages = Int(fields[1]) else { return nil }
        return pages * Int(sysconf(Int32(_SC_PAGESIZE)))
        #else
        let child = try? ChildProcess(executable: "/bin/ps", arguments: ["-o", "rss=", "-p", "\(pid)"], discardStderr: true)
        guard let child else { return nil }
        try? child.stdin.close()
        let output = child.stdout.readDataToEndOfFile()
        child.wait(timeout: 5)
        let text = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(text).map { $0 * 1024 }
        #endif
    }
}
