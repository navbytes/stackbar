import Foundation

/// Runs `body` in its own autorelease pool on macOS (directly elsewhere).
///
/// Long-lived reader threads (`Thread { while true { handle.availableData … } }`)
/// need one per iteration: on macOS `availableData` and the bridging behind
/// decoding return autoreleased objects, and a plain `Thread`'s outer pool
/// drains only when the thread ends, so memory would grow with every chunk.
public func withAutoreleasePool<T>(_ body: () throws -> T) rethrows -> T {
    #if canImport(Darwin)
    return try autoreleasepool(invoking: body)
    #else
    return try body()
    #endif
}
