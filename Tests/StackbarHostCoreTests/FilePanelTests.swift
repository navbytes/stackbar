import Foundation
import XCTest
import StackbarProtocol
@testable import StackbarHostCore

final class FilePanelTests: XCTestCase {
    private func services(_ system: SimulatedSystem) -> HostServices {
        HostServices.local(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), secrets: MemorySecretStore([:]), platform: .init(system: system))
    }

    private let manifest = Manifest(id: "dev.test.files", name: "Files")

    func testChooseFileNeedsNoCapabilityAndAnswersNilOnCancel() async throws {
        let system = SimulatedSystem()
        let services = services(system)
        system.simulate(chosenFile: ChosenFile(name: "links.json", data: Data("[]".utf8)))
        guard case .value(let json?) = await services.handle(.chooseFile(types: ["json"]), for: manifest) else { return XCTFail("no file") }
        XCTAssertEqual(try SystemCodec.decode(ChosenFile.self, from: json), ChosenFile(name: "links.json", data: Data("[]".utf8)))
        system.simulate(chosenFile: nil)
        let cancelled = await services.handle(.chooseFile(types: []), for: manifest)
        XCTAssertEqual(cancelled, .value(nil))
        system.simulate(chosenFile: ChosenFile(name: "big.bin", data: Data(count: ChosenFile.maxBytes + 1)))
        guard case .failure = await services.handle(.chooseFile(types: []), for: manifest) else { return XCTFail("took a file over 5 MB") }
    }

    func testSaveFileKeepsOnlyTheFileName() async {
        let system = SimulatedSystem()
        let result = await services(system).handle(.saveFile(name: "../../etc/quicklinks.json", data: Data("[]".utf8)), for: manifest)
        XCTAssertEqual(result, .value("/Users/you/Downloads/quicklinks.json"))
        XCTAssertEqual(system.saved.first?.name, "quicklinks.json")
    }

    func testResolveApplicationByNamePathOrID() async {
        let services = services(SimulatedSystem())
        for (input, expected) in [("Safari", "com.apple.Safari"), ("google chrome", "com.google.Chrome"), ("/Applications/Xcode.app", "com.apple.dt.Xcode"), ("com.apple.finder", "com.apple.finder"), ("Nope", nil)] {
            let result = await services.handle(.resolveApplication(input), for: manifest)
            XCTAssertEqual(result, .value(expected), input)
        }
    }
}
