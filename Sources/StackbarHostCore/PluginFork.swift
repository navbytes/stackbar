import Foundation

/// Copying a plugin to change it. `PluginEditor` opens an agent on the copy.
public enum PluginFork {
    /// The source with its manifest's `id:` and `name:` replaced, so the copy
    /// runs next to the original with its own storage and approvals.
    public static func fork(_ source: String, name: String, id: String) -> String {
        var result = source
        result = replaceFirst(#"id:\s*"[^"]*""#, in: result, with: "id: \"\(id)\"")
        result = replaceFirst(#"name:\s*"[^"]*""#, in: result, with: "name: \"\(name.replacingOccurrences(of: "\"", with: "'"))\"")
        return result
    }

    /// Writes a fork of `file` next to it and returns the new file.
    public static func forkFile(_ file: URL, in directory: URL, name: String) throws -> URL {
        let source = try String(contentsOf: file, encoding: .utf8)
        let base = PluginTemplate.typeName(for: name)
        var target = directory.appendingPathComponent("\(base).swift")
        var counter = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = directory.appendingPathComponent("\(base)\(counter).swift")
            counter += 1
        }
        let id = "dev.local." + target.deletingPathExtension().lastPathComponent.lowercased()
        try fork(source, name: name, id: id).write(to: target, atomically: true, encoding: .utf8)
        return target
    }

    private static func replaceFirst(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return text }
        return text.replacingCharacters(in: range, with: replacement)
    }
}
