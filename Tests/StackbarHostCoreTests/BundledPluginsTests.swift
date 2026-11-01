import Foundation
import XCTest
@testable import StackbarHostCore

final class BundledPluginsTests: XCTestCase {
    func testUpdatesUntouchedAndStaleCopiesButKeepsEdits() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let shipped = root.appendingPathComponent("shipped")
        let plugins = root.appendingPathComponent("plugins")
        try FileManager.default.createDirectory(at: shipped, withIntermediateDirectories: true)
        let bundled = BundledPlugins(directory: plugins, recordFile: root.appendingPathComponent("bundled.json"))
        func ship(_ name: String, _ text: String) throws -> URL {
            let url = shipped.appendingPathComponent(name)
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        func installed(_ name: String) -> String? { try? String(contentsOf: plugins.appendingPathComponent(name), encoding: .utf8) }

        // A pre-rename copy with no record is replaced and kept as .bak.
        try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
        try "import FluidKit\n".write(to: plugins.appendingPathComponent("UpNext.swift"), atomically: true, encoding: .utf8)
        var sources = [try ship("UpNext.swift", "import StackbarKit // 1\n"), try ship("Clipboard.swift", "import StackbarKit // 1\n")]

        // At launch only what's there is refreshed.
        var result = bundled.sync(sources, installMissing: false)
        XCTAssertEqual(result.updated.map(\.lastPathComponent), ["UpNext.swift"])
        XCTAssertEqual(installed("UpNext.swift"), "import StackbarKit // 1\n")
        XCTAssertEqual(installed("UpNext.swift.bak"), "import FluidKit\n")
        XCTAssertNil(installed("Clipboard.swift"), "a missing plugin isn't installed at launch")

        result = bundled.sync(sources)
        XCTAssertEqual(result.installed.map(\.lastPathComponent), ["Clipboard.swift"])

        // A new version replaces an untouched copy but not an edited one.
        try "import StackbarKit // mine\n".write(to: plugins.appendingPathComponent("Clipboard.swift"), atomically: true, encoding: .utf8)
        sources = [try ship("UpNext.swift", "import StackbarKit // 2\n"), try ship("Clipboard.swift", "import StackbarKit // 2\n")]
        result = bundled.sync(sources, installMissing: false)
        XCTAssertEqual(result.updated.map(\.lastPathComponent), ["UpNext.swift"])
        XCTAssertEqual(result.kept.map(\.lastPathComponent), ["Clipboard.swift"])
        XCTAssertEqual(installed("UpNext.swift"), "import StackbarKit // 2\n")
        XCTAssertEqual(installed("Clipboard.swift"), "import StackbarKit // mine\n")
    }
}
