import Foundation
import XCTest
@testable import StackbarHostCore

final class StackbarPackageTests: XCTestCase {
    /// The installer links `~/.local/bin/stackbarctl` to the copy inside the
    /// app; plugin builds must find the StackbarKit the app carries through
    /// that link, not the checkout the release was built in.
    func testALinkedStackbarctlFindsTheAppsStackbarKit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true).resolvingSymlinksInPath()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("Stackbar.app/Contents", isDirectory: true)
        let kit = contents.appendingPathComponent("Resources/StackbarKit", isDirectory: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: kit, withIntermediateDirectories: true)
        try Data().write(to: kit.appendingPathComponent("Package.swift"))
        let executable = contents.appendingPathComponent("MacOS/stackbarctl")
        try Data().write(to: executable)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let link = bin.appendingPathComponent("stackbarctl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: executable)

        XCTAssertEqual(StackbarPaths.bundledPackage(beside: link)?.standardizedFileURL.path, kit.standardizedFileURL.path)
        XCTAssertEqual(StackbarPaths.bundledPackage(beside: executable)?.standardizedFileURL.path, kit.standardizedFileURL.path)
        guard ProcessInfo.processInfo.environment["STACKBAR_PACKAGE"] == nil else { return }
        XCTAssertEqual(StackbarPaths.stackbarPackage(executable: link).standardizedFileURL.path, kit.standardizedFileURL.path)
    }

    /// Outside an app bundle (a checkout's own build), the source checkout.
    func testOutsideAnAppTheSourceCheckoutIsUsed() {
        guard ProcessInfo.processInfo.environment["STACKBAR_PACKAGE"] == nil else { return }
        let package = StackbarPaths.stackbarPackage(sourceFile: "/src/stackbar/Sources/StackbarHostCore/StackbarPaths.swift", executable: URL(fileURLWithPath: "/nowhere/bin/stackbarctl"))
        XCTAssertEqual(package.path, "/src/stackbar")
        XCTAssertNotNil(StackbarPaths.runningExecutable, "the test runner has an executable path")
    }
}
