import XCTest
@testable import StackbarHostCore

/// The one way the host's stores read and write their JSON files.
final class JSONFileTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("json-file-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private struct Record: Codable, Equatable {
        var name: String
        var at: Date
    }

    func testWritesIntoAFolderThatDoesNotExistYetAndReadsItBack() throws {
        let file = directory.appendingPathComponent("deep/er/state.json")
        try JSONFile.write(["b": 2, "a": 1], to: file)
        XCTAssertEqual(JSONFile.read([String: Int].self, from: file), ["a": 1, "b": 2])
    }

    func testAMissingDamagedOrMistypedFileReadsAsNothing() throws {
        let file = directory.appendingPathComponent("state.json")
        XCTAssertNil(JSONFile.read([String].self, from: nil), "a store kept in memory has no file")
        XCTAssertNil(JSONFile.read([String].self, from: file), "no file yet")
        try JSONFile.write(Data("{ not json".utf8), to: file)
        XCTAssertNil(JSONFile.read([String].self, from: file), "a damaged file")
        try JSONFile.write(["a": 1], to: file)
        XCTAssertNil(JSONFile.read([String].self, from: file), "another type's file")
    }

    func testAWriteReplacesTheWholeFile() throws {
        let file = directory.appendingPathComponent("state.json")
        try JSONFile.write(["one", "two", "three"], to: file)
        try JSONFile.write(["one"], to: file)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), #"["one"]"#)
    }

    func testAWriteThatCannotLandThrows() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        XCTAssertThrowsError(try JSONFile.write([1], to: blocker.appendingPathComponent("state.json")), "its folder is a file")
    }

    /// What is on users' disks: the stores' files keep the bytes they had
    /// before they shared this helper.
    func testReadableAndLedgerFilesKeepTheirFormat() throws {
        let file = directory.appendingPathComponent("state.json")
        try JSONFile.write(["b": ["y", "x"], "a": []], to: file, encoder: .readable)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), """
        {
          "a" : [

          ],
          "b" : [
            "y",
            "x"
          ]
        }
        """)

        let record = Record(name: "n", at: Date(timeIntervalSince1970: 0))
        try JSONFile.write(record, to: file, encoder: .ledger)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), """
        {
          "at" : "1970-01-01T00:00:00Z",
          "name" : "n"
        }
        """)
        XCTAssertEqual(JSONFile.read(Record.self, from: file, decoder: .ledger), record)
        XCTAssertNil(JSONFile.read(Record.self, from: file), "an ISO date needs the ledger's decoder")
    }

    /// The stores that moved onto the helper still find what an earlier
    /// version of the app wrote, and write it where they did.
    func testStoresReadWhatTheyWroteBefore() throws {
        let grantsFile = directory.appendingPathComponent("folder-grants.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"dev.t.a":["/tmp"]}"#.utf8).write(to: grantsFile)
        XCTAssertEqual(FolderGrants(file: grantsFile).folders(for: "dev.t.a"), ["/tmp"])

        let favoritesFile = directory.appendingPathComponent("palette-favorites.json")
        try Data(#"["one","two"]"#.utf8).write(to: favoritesFile)
        let favorites = PaletteFavorites(file: favoritesFile)
        XCTAssertEqual(favorites.ids, ["one", "two"])
        favorites.toggle("three")
        XCTAssertEqual(try String(contentsOf: favoritesFile, encoding: .utf8), #"["one","two","three"]"#)

        let consentFile = directory.appendingPathComponent("nested/agent-consent.json")
        let consent = AgentConsent(file: consentFile)
        consent.set(false, pluginID: "dev.t.a", tool: "laps", specs: [])
        XCTAssertEqual(try String(contentsOf: consentFile, encoding: .utf8), #"{"dev.t.a":{"laps":false}}"#)
        XCTAssertFalse(AgentConsent(file: consentFile).allows(pluginID: "dev.t.a", tool: "laps", specs: []))
    }
}
