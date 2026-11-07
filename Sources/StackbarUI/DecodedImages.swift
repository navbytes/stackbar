#if canImport(AppKit)
import AppKit

/// Pictures decoded once and kept, for views that draw one on every body
/// pass: a remote image in a plugin's tree, a clipboard image under a
/// selected row. Decoding in a body repeated the work on each redraw
/// (every tick of a plugin, every arrow press in the palette).
@MainActor
public enum DecodedImages {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 128
        // Bytes of the encoded data, as a rough size.
        cache.totalCostLimit = 96 * 1_024 * 1_024
        return cache
    }()

    /// The picture kept under `key`, else decoded from what `data` returns
    /// (called only then, so a lookup that reads a file isn't repeated) and
    /// kept. `key` must name the bytes: a content id, or a URL with its size.
    public static func image(key: String, data: () -> Data?) -> NSImage? {
        if let kept = cache.object(forKey: key as NSString) { return kept }
        guard let data = data(), let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key as NSString, cost: data.count)
        return image
    }
}
#endif
