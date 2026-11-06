#if os(macOS)
import AppKit
import CoreServices
import StackbarHostCore
import StackbarProtocol

extension MacSystem {
    func pickColor() async throws -> PickedColor? {
        await MacColorPicker.pick()
    }

    func define(_ word: String) async -> Definition? {
        MacDictionary.define(word)
    }
}

/// The system magnifier (`NSColorSampler`), one at a time.
@MainActor
enum MacColorPicker {
    /// Held while it shows: the sampler goes away when nothing keeps it.
    private static var sampler: NSColorSampler?

    static func pick() async -> PickedColor? {
        guard sampler == nil else { return nil }
        let sampler = NSColorSampler()
        self.sampler = sampler
        // The magnifier needs Stackbar in front to take the click.
        NSApp.activate()
        let color: NSColor? = await withCheckedContinuation { continuation in
            sampler.show { picked in continuation.resume(returning: picked) }
        }
        self.sampler = nil
        guard let srgb = color?.usingColorSpace(.sRGB) else { return nil }
        return PickedColor(red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent), alpha: Double(srgb.alphaComponent))
    }
}

/// The Dictionary app's definitions (Dictionary Services), offline.
enum MacDictionary {
    static func define(_ word: String) -> Definition? {
        let length = (word as NSString).length
        guard length > 0, let text = DCSCopyTextDefinition(nil, word as CFString, CFRange(location: 0, length: length))?.takeRetainedValue() else { return nil }
        let definition = (text as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return definition.isEmpty ? nil : Definition(word: word, text: definition)
    }
}
#endif
