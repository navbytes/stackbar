#if canImport(AppKit) && canImport(ImageIO)
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Joins PNG frames into one animated PNG (APNG), which every current
/// browser plays as an `<img>`. Frames may differ in height (a panel grows
/// as it fills): each is drawn at the top of a canvas as large as the
/// largest, and the rest is filled with the colour of its bottom-left pixel
/// so the panel's background just continues. `stackbarctl render --frames`
/// uses it for the store's demo loops.
public enum AnimatedPNG {
    public static func make(_ frames: [(png: Data, seconds: Double)], loops: Int = 0) -> Data? {
        let images = frames.compactMap { frame -> (CGImage, Double)? in
            guard let source = CGImageSourceCreateWithData(frame.png as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            return (image, frame.seconds)
        }
        guard !images.isEmpty, images.count == frames.count else { return nil }
        let width = images.map { $0.0.width }.max()!
        let height = images.map { $0.0.height }.max()!
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, images.count, nil) else { return nil }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: loops]] as CFDictionary)
        for (image, seconds) in images {
            guard let canvas = padded(image, width: width, height: height) else { return nil }
            CGImageDestinationAddImage(destination, canvas, [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: seconds, kCGImagePropertyAPNGUnclampedDelayTime: seconds]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func padded(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if let fill = bottomLeft(of: image) {
            context.setFillColor(fill)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        // Core Graphics counts y from the bottom: keep the frame at the top.
        context.draw(image, in: CGRect(x: 0, y: height - image.height, width: image.width, height: image.height))
        return context.makeImage()
    }

    private static func bottomLeft(of image: CGImage) -> CGColor? {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Draw the image so that its bottom-left pixel (inset by 2, clear of
        // any rounded corner) lands on the 1×1 context.
        context.draw(image, in: CGRect(x: -2, y: -2, width: image.width, height: image.height))
        return CGColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: CGFloat(pixel[3]) / 255)
    }
}
#endif
