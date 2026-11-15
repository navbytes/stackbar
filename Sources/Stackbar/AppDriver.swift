#if os(macOS)
import AppKit

/// What the app check (`AppCheck`) and the benchmark (`Benchmark`) both do
/// to the running app: wait for a state on the main actor, let AppKit draw,
/// and time how long the palette takes to open.
@MainActor
enum AppDriver {
    /// Polls every 10 ms on the main actor; true once `condition` holds.
    static func waitUntil(seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// After AppKit has drawn: the next pass of the run loop.
    static func nextFrame() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    /// Milliseconds, to a tenth.
    static func ms(_ seconds: TimeInterval) -> Double { (seconds * 10_000).rounded() / 10 }

    static func ms(since start: Date) -> Double { ms(Date().timeIntervalSince(start)) }

    /// Opens and hides the palette `times` times, `pause` apart; how long
    /// each open took until it was on screen and drawn, in ms.
    static func paletteOpens(_ app: AppDelegate, times: Int = 10, pause: Duration) async -> [Double] {
        var opens: [Double] = []
        for _ in 0..<times {
            let start = Date()
            app.palette.toggle()
            _ = await waitUntil(seconds: 5) { app.palette.isVisible }
            await nextFrame()
            opens.append(ms(since: start))
            app.palette.hide()
            try? await Task.sleep(for: pause)
        }
        return opens
    }
}
#endif
