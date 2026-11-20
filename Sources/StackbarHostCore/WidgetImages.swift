import Foundation
#if canImport(ImageIO)
import ImageIO
import UniformTypeIdentifiers
#endif

/// Remote images made ready for the widget extension.
///
/// A widget extension runs in a few tens of megabytes, and a widget is at
/// most a few hundred points across, so an album cover or avatar fetched at
/// full size is scaled down before it is written to the app group.
public enum WidgetImages {
    /// The longest side, in pixels, an image keeps: a large widget at 2x.
    public static let maxPixels = 800
    /// The most images one widget may show; the rest draw their placeholders.
    public static let maxPerWidget = 12

    /// `data` scaled so its longest side is at most `maxPixels`, or as it is
    /// when it is already that small or can't be read as an image.
    public static func downsampled(_ data: Data, maxPixels: Int = WidgetImages.maxPixels) -> Data {
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return data }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard max(width, height) > maxPixels else { return data }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return data }
        let output = NSMutableData()
        let hasAlpha = ![CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(thumbnail.alphaInfo)
        let type = (hasAlpha ? UTType.png : UTType.jpeg).identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return data }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return data }
        return output as Data
        #else
        return data
        #endif
    }
}
