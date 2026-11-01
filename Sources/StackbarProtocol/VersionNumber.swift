/// A dotted version (`0.10.0`, `1.2`), compared part by part, so `0.10.0` is
/// newer than `0.9.3`. Missing parts count as zero. A pre-release suffix
/// (`1.0.0-beta.1`) sorts before the release with the same numbers.
public struct VersionNumber: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let parts: [Int]
    public let prerelease: String?

    public init?(_ text: String) {
        let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let pieces = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = pieces[0].split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(numbers.count) else { return nil }
        var parts: [Int] = []
        for number in numbers {
            guard !number.isEmpty, number.allSatisfy(\.isASCII), let value = Int(number), value >= 0 else { return nil }
            parts.append(value)
        }
        if pieces.count == 2 && pieces[1].isEmpty { return nil }
        self.parts = parts
        self.prerelease = pieces.count == 2 ? String(pieces[1]) : nil
    }

    public var description: String {
        parts.map(String.init).joined(separator: ".") + (prerelease.map { "-\($0)" } ?? "")
    }

    public static func < (lhs: VersionNumber, rhs: VersionNumber) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for position in 0..<count {
            let left = position < lhs.parts.count ? lhs.parts[position] : 0
            let right = position < rhs.parts.count ? rhs.parts[position] : 0
            if left != right { return left < right }
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil), (nil, _?): return false
        case (_?, nil): return true
        case let (left?, right?): return left < right
        }
    }

    public static func == (lhs: VersionNumber, rhs: VersionNumber) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public func hash(into hasher: inout Hasher) {
        var trimmed = parts
        while trimmed.last == 0 { trimmed.removeLast() }
        hasher.combine(trimmed)
        hasher.combine(prerelease)
    }
}
