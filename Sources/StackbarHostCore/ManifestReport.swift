import Foundation
import StackbarProtocol

/// What `stackbarctl manifest --json` prints: the manifest the code declares
/// and what is wrong with it, so a store's lint reads the real manifest
/// instead of parsing Swift source.
public struct ManifestReport: Codable, Equatable, Sendable {
    public var manifest: Manifest
    /// Why the host would refuse to run it (`Manifest.problems`).
    public var problems: [String]
    /// Why an index would refuse to list it (`Manifest.publishingProblems`).
    public var publishingProblems: [String]

    public init(_ manifest: Manifest) {
        self.manifest = manifest
        problems = manifest.problems
        publishingProblems = manifest.publishingProblems
    }

    /// Pretty-printed with sorted keys, so the output is stable to diff.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
