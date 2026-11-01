import Foundation
import XCTest
@testable import StackbarHostCore
import StackbarProtocol

final class RemoteImageTests: XCTestCase {
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0])

    func testOnlyHTTPSImagesAreFetched() {
        XCTAssertTrue(RemoteImageStore.isFetchable("https://i.scdn.co/image/abc"))
        XCTAssertFalse(RemoteImageStore.isFetchable("http://i.scdn.co/image/abc"))
        XCTAssertFalse(RemoteImageStore.isFetchable("file:///etc/passwd"))
        XCTAssertFalse(RemoteImageStore.isFetchable("not a url"))
        XCTAssertTrue(RemoteImageStore.isImage(contentType: "image/jpeg", body: Data([1])))
        XCTAssertFalse(RemoteImageStore.isImage(contentType: "text/html", body: png))
        XCTAssertTrue(RemoteImageStore.isImage(contentType: "application/octet-stream", body: png))
        XCTAssertTrue(RemoteImageStore.isImage(contentType: nil, body: png))
        XCTAssertFalse(RemoteImageStore.isImage(contentType: nil, body: Data("<html>".utf8)))
    }

    func testUndeclaredHostsAreRefusedAndAudited() async {
        let audit = NetworkAudit()
        let store = RemoteImageStore(http: HTTPService(audit: audit))
        let tree = ViewNode.image(.url("https://images.example.com/a.png", placeholder: nil))
        let loaded = await store.load(tree, pluginID: "io.test.images", allowedHosts: ["api.example.com"])
        XCTAssertEqual(loaded, [])
        XCTAssertNil(store.data(for: "https://images.example.com/a.png"))
        XCTAssertEqual(audit.report(for: Manifest(id: "io.test.images", name: "Images")).undeclared, ["images.example.com"])
    }

    func testKeptImagesAreServedAndTheOldestDropped() {
        let store = RemoteImageStore(http: HTTPService(audit: NetworkAudit()))
        for index in 0...RemoteImageStore.capacity {
            store.insert(png, for: "https://example.com/\(index).png")
        }
        XCTAssertNil(store.data(for: "https://example.com/0.png"))
        XCTAssertEqual(store.data(for: "https://example.com/\(RemoteImageStore.capacity).png"), png)
    }

    func testAgentTextNamesRemoteImagesAndGridCells() {
        let tree = ViewNode.grid(columns: 2, children: [.image(.url("https://example.com/a.png", placeholder: nil)), .text("Docs")])
        XCTAssertEqual(TreeTextRenderer.render(tree), "[image]\nDocs")
    }
}
