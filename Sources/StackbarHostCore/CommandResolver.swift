import Foundation
import StackbarProtocol

/// Finds the program a declared command name means.
///
/// A bare name is looked up on one fixed search path, never the user's PATH:
/// PATH can be changed by a dotfile or point into a folder anyone can write
/// to, and what the user approved must stay the program that runs.
public struct CommandResolver: Sendable {
    public static let searchPath = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    public static let standard = CommandResolver()

    /// Programs that run whatever they are given, flagged on the install
    /// sheet as able to run any program.
    public static let interpreters: Set<String> = [
        "sh", "bash", "zsh", "fish", "dash", "ksh", "tcsh", "csh", "env", "osascript", "xargs", "sudo",
        "python", "python3", "node", "deno", "bun", "ruby", "perl", "php", "swift", "lua", "tclsh", "pwsh",
    ]

    public var directories: [String]
    private let isExecutable: @Sendable (String) -> Bool

    public init(directories: [String] = CommandResolver.searchPath, isExecutable: @escaping @Sendable (String) -> Bool = CommandResolver.isExecutableFile) {
        self.directories = directories
        self.isExecutable = isExecutable
    }

    /// The absolute path `name` runs, or `nil` when there is none. An
    /// absolute name resolves to itself when it is an executable file.
    public func resolve(_ name: String) -> String? {
        guard Self.isValidName(name) else { return nil }
        if name.hasPrefix("/") {
            let path = URL(fileURLWithPath: name).standardizedFileURL.path
            return isExecutable(path) ? path : nil
        }
        for directory in directories {
            let path = directory + "/" + name
            if isExecutable(path) { return path }
        }
        return nil
    }

    /// Every declared name with what it resolves to now.
    public func resolve(all names: [String]) -> [String: String] {
        names.reduce(into: [:]) { result, name in
            if let path = resolve(name) { result[name] = path }
        }
    }

    /// A bare name (no slash) or an absolute path; nothing relative.
    public static func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 1024, !name.contains("\0") else { return false }
        if name.hasPrefix("/") { return true }
        return !name.contains("/") && name != "." && name != ".."
    }

    public static func isInterpreter(_ nameOrPath: String) -> Bool {
        let base = (nameOrPath as NSString).lastPathComponent
        if interpreters.contains(base) { return true }
        // python3.12, ruby3.3, node20…
        let stem = String(base.prefix { !$0.isNumber && $0 != "." })
        return ["python", "ruby", "node", "perl", "php", "lua"].contains(stem)
    }

    @Sendable public static func isExecutableFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)
    }
}

extension Manifest {
    /// Every command name the manifest's `.run` capabilities declare.
    public var runCommands: [String] {
        capabilities.flatMap { capability -> [String] in
            if case .run(let commands) = capability { return commands }
            return []
        }
    }
}
