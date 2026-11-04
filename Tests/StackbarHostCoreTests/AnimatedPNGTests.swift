#if canImport(StackbarUI) && os(macOS)
import AppKit
import ImageIO
import XCTest
import StackbarUI

/// `stackbarctl render --frames` joins snapshots with AnimatedPNG; the store's
/// demo loops are these files. Only macOS has ImageIO, so Linux skips them.
@MainActor
final class AnimatedPNGTests: XCTestCase {
    /// A solid PNG of exactly `width` × `height` pixels (no screen scale).
    private func png(width: Int, height: Int, gray: CGFloat) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
    }

    func testJoinsFramesWithTheirDelaysAndTheTallestSize() throws {
        let data = try XCTUnwrap(AnimatedPNG.make([
            (png(width: 40, height: 20, gray: 0.2), 1.5),
            (png(width: 40, height: 30, gray: 0.8), 0.35),
        ]))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 2)
        var delays: [Double] = []
        for index in 0..<2 {
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, index, nil))
            XCTAssertEqual(image.height, 30, "every frame is as tall as the tallest")
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let png = properties?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
            delays.append((png?[kCGImagePropertyAPNGUnclampedDelayTime] ?? png?[kCGImagePropertyAPNGDelayTime]) as? Double ?? 0)
        }
        XCTAssertEqual(delays[0], 1.5, accuracy: 0.01)
        XCTAssertEqual(delays[1], 0.35, accuracy: 0.01)
    }

    func testNoFramesOrAnUnreadableOneGiveNothing() {
        XCTAssertNil(AnimatedPNG.make([]))
        XCTAssertNil(AnimatedPNG.make([(Data("not a png".utf8), 1)]))
    }
}
#endif
