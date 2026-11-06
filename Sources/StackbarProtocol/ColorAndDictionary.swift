import Foundation

// Values for the color picker and dictionary calls (protocol 21).

/// A color the user picked from the screen, in sRGB.
public struct PickedColor: Codable, Equatable, Hashable, Sendable {
    /// 0 to 1 each.
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    /// `#RRGGBB`, uppercased.
    public var hex: String {
        String(format: "#%02X%02X%02X", Self.byte(red), Self.byte(green), Self.byte(blue))
    }

    /// `rgb(10, 96, 200)`.
    public var rgb: String { "rgb(\(Self.byte(red)), \(Self.byte(green)), \(Self.byte(blue)))" }

    /// `hsl(213, 90%, 41%)`.
    public var hsl: String {
        let (hue, saturation, lightness) = hslComponents
        return "hsl(\(Int(hue.rounded())), \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%)"
    }

    /// Hue in degrees, saturation and lightness from 0 to 1.
    public var hslComponents: (hue: Double, saturation: Double, lightness: Double) {
        let high = max(red, green, blue), low = min(red, green, blue)
        let lightness = (high + low) / 2
        guard high != low else { return (0, 0, lightness) }
        let delta = high - low
        let saturation = lightness > 0.5 ? delta / (2 - high - low) : delta / (high + low)
        var hue: Double
        switch high {
        case red: hue = (green - blue) / delta + (green < blue ? 6 : 0)
        case green: hue = (blue - red) / delta + 2
        default: hue = (red - green) / delta + 4
        }
        hue *= 60
        return (hue, saturation, lightness)
    }

    /// `#RRGGBB` or `#RGB`, with or without the #.
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    static func byte(_ value: Double) -> Int { Int((clamp(value) * 255).rounded()) }
    static func clamp(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
}

/// What the Mac's Dictionary says about a word.
public struct Definition: Codable, Equatable, Sendable {
    /// The word or phrase the definition is for, as the dictionary matched it.
    public var word: String
    /// The definition as plain text, at most `maxLength` characters.
    public var text: String

    public static let maxLength = 20_000
    /// The longest word or phrase the host looks up.
    public static let maxQuery = 100

    public init(word: String, text: String) {
        self.word = word
        self.text = String(text.prefix(Self.maxLength))
    }
}
