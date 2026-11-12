import XCTest
@testable import StackbarProtocol

/// A plugin's line must never crash the host, however wrong it is: every
/// line from a helper goes through `LineCodec.decode(PluginMessage.self)`
/// in the host process (openspec/changes/trust-first, task 3.2). These feed
/// it mutated, extreme and deeply nested messages; a trap or a stack
/// overflow fails the whole test run, so passing means none happened.
final class DecoderFuzzTests: XCTestCase {
    /// Deterministic, so a failure reproduces.
    private struct Rand {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 11
        }
        mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
    }

    private func seeds() throws -> [Data] {
        let tree = ViewNode.stack(axis: .vertical, spacing: 4, children: [
            .text("Hello", style: .headline),
            .label("Run", symbol: "play"),
            .list(searchable: true, children: [.section(title: "A", children: [.badge("1"), .text("x")])]),
        ])
        let messages: [PluginMessage] = [
            .ready(protocolVersion: 29),
            .settled,
            .log(level: .info, message: "hello"),
            .render(surface: .panel, root: tree),
            .view(session: 1, seq: 2, root: tree),
            .request(id: 7, call: .storageSet(key: "k", value: "v")),
            .request(id: 8, call: .secret(name: "TOKEN")),
            .commands([CommandSpec(id: "search", title: "Search Things")]),
            .menuBarClick(MenuBarClick(title: "Toggle", action: "toggle")),
            .toolResult(id: 3, text: "ok", isError: false),
        ]
        return try messages.map { try LineCodec.encode($0) }
    }

    /// Decodes, and for what decodes, does what the host does next with it:
    /// encodes it again and describes a host call.
    private func feed(_ line: Data) {
        guard let message = try? LineCodec.decode(PluginMessage.self, from: line) else { return }
        _ = try? LineCodec.encode(message)
        if case .request(_, let call) = message { _ = call.label }
    }

    nonisolated(unsafe) private static let extremeNumbers: [Any] = [-1, 0, Int.min, Int.max, Int64.max, 1e308, -1e308, 0.5, -0.0, UInt64.max]
    private static let extremeStrings: [String] = ["", String(repeating: "é", count: 5_000), "\u{0}", "../../etc", "%@%n", "\u{202E}abc"]

    /// Replaces values in the JSON tree. Only one array per message is
    /// blown up to many copies, so a message stays a few MB at most.
    private func mutate(_ value: Any, _ rand: inout Rand) -> Any {
        var grown = false
        return mutate(value, &rand, grown: &grown)
    }

    private func mutate(_ value: Any, _ rand: inout Rand, grown: inout Bool) -> Any {
        switch value {
        case let object as [String: Any]:
            var copy: [String: Any] = [:]
            for (key, inner) in object where rand.below(12) != 0 {   // sometimes drop a key
                copy[key] = mutate(inner, &rand, grown: &grown)
            }
            if rand.below(10) == 0 { copy["unexpected"] = Self.extremeNumbers[rand.below(Self.extremeNumbers.count)] }
            return copy
        case let array as [Any]:
            var copy: [Any] = []
            for inner in array { copy.append(mutate(inner, &rand, grown: &grown)) }
            switch rand.below(8) {
            case 0: copy = []
            case 1 where !grown:
                grown = true
                copy = Array(repeating: copy.first ?? 0, count: 2_000)
            case 2: copy.append(NSNull())
            default: break
            }
            return copy
        case is String:
            switch rand.below(4) {
            case 0: return Self.extremeStrings[rand.below(Self.extremeStrings.count)]
            case 1: return Self.extremeNumbers[rand.below(Self.extremeNumbers.count)]
            default: return value
            }
        case is NSNumber:
            switch rand.below(3) {
            case 0: return Self.extremeNumbers[rand.below(Self.extremeNumbers.count)]
            case 1: return "12"
            default: return value
            }
        default:
            return rand.below(3) == 0 ? [Any]() : value
        }
    }

    func testMutatedMessagesNeverCrashTheHost() throws {
        var rand = Rand(state: 0x5EED)
        for seed in try seeds() {
            let tree = try JSONSerialization.jsonObject(with: seed, options: [.fragmentsAllowed])
            for _ in 0..<100 {
                let mutated = mutate(tree, &rand)
                guard JSONSerialization.isValidJSONObject(mutated) || mutated is String || mutated is NSNumber,
                      let data = try? JSONSerialization.data(withJSONObject: mutated, options: [.fragmentsAllowed]) else { continue }
                feed(data)
            }
        }
    }

    func testBytesNeverCrashTheHost() throws {
        var rand = Rand(state: 0xB17E5)
        for seed in try seeds() {
            for _ in 0..<500 {
                var bytes = [UInt8](seed)
                for _ in 0...rand.below(4) where !bytes.isEmpty {
                    let at = rand.below(bytes.count)
                    switch rand.below(3) {
                    case 0: bytes[at] = UInt8(truncatingIfNeeded: rand.next())
                    case 1: bytes.remove(at: at)
                    default: bytes.insert(bytes[at], at: at)
                    }
                }
                feed(Data(bytes))
            }
        }
    }

    /// A view nested far deeper than any real one. The host must refuse it,
    /// not overflow its stack decoding it.
    func testDeeplyNestedViewsNeverCrashTheHost() throws {
        let leaf = String(decoding: try LineCodec.encode(ViewNode.text("x")), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let wrapped = String(decoding: try LineCodec.encode(ViewNode.stack(axis: .vertical, children: [.text("x")])), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let range = try XCTUnwrap(wrapped.range(of: leaf))
        let prefix = String(wrapped[..<range.lowerBound]), suffix = String(wrapped[range.upperBound...])
        let render = String(decoding: try LineCodec.encode(PluginMessage.render(surface: .panel, root: .text("x"))), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let slot = try XCTUnwrap(render.range(of: leaf))
        for depth in [100, 1_000, 10_000, 100_000] {
            let nested = String(repeating: prefix, count: depth) + leaf + String(repeating: suffix, count: depth)
            let line = Data(render.replacingCharacters(in: slot, with: nested).utf8)
            if depth == 100 {
                XCTAssertNotNil(try? LineCodec.decode(PluginMessage.self, from: line), "a nested view of 100 decodes, so the template is right")
            }
            feed(line)
            // Bare arrays, which the JSON scanner sees before any type.
            let arrays = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
            feed(Data(render.replacingCharacters(in: slot, with: arrays).utf8))
        }
    }
}
