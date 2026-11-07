#if os(macOS)
import ApplicationServices
import Foundation

/// Where Accessibility messages to other apps are sent from: one serial
/// queue off the main thread. Each message waits for the other app to
/// answer, up to its messaging timeout, and a hung or busy app (or a menu
/// bar of thousands of items) must not hold up the main thread, which also
/// runs the keyboard taps.
///
/// Elements never leave the closure that made them: work from a process id,
/// and hand back plain values.
enum AXWorker {
    /// How long one message may wait for an app that doesn't answer. The
    /// timeout is per element and isn't passed on to the elements read from
    /// it, so set it with `timed` on each one.
    static let timeout: Float = 0.25

    private static let queue = DispatchQueue(label: "io.navbytes.stackbar.accessibility", qos: .userInitiated)

    /// Runs `body` on the worker queue and answers its result.
    static func run<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: body()) }
        }
    }

    /// Runs `body` on the worker queue and answers its result or error.
    static func runThrowing<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try body() }) }
        }
    }

    /// Runs `body` on the worker queue without waiting for it.
    static func send(_ body: @escaping @Sendable () -> Void) {
        queue.async(execute: body)
    }

    /// The element, with its messaging timeout set.
    @discardableResult
    static func timed(_ element: AXUIElement, _ seconds: Float = timeout) -> AXUIElement {
        AXUIElementSetMessagingTimeout(element, seconds)
        return element
    }
}
#endif
