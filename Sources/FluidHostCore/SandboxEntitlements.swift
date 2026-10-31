import Foundation
import FluidProtocol

/// Turns a manifest's capabilities into the App Sandbox entitlements its helper
/// is signed with, so the OS — not the honour system — limits what it touches.
///
/// The sandbox has no per-domain network switch: `network(hosts:)` can only
/// turn outgoing connections on. The host keeps the domain list for the install
/// sheet and for comparing against what the plugin actually connects to.
public enum SandboxEntitlements {
    public static func entitlements(for manifest: Manifest) -> [String: Bool] {
        var result = ["com.apple.security.app-sandbox": true]
        for capability in manifest.capabilities {
            switch capability {
            case .network, .oauth:
                result["com.apple.security.network.client"] = true
            case .files, .run, .secret, .clipboard, .power, .calendar:
                // Files are opened up path by path (`fileExceptions`).
                // Children inherit the sandbox; secrets, the clipboard, power
                // assertions and calendar events all go through the host.
                break
            }
        }
        return result
    }

    /// The `.files` paths as sandbox file exceptions: `~/x` paths relative
    /// to the home folder, the rest absolute. A path that is a folder (or
    /// doesn't exist yet) ends in a slash, which covers everything inside it.
    public static func fileExceptions(for manifest: Manifest, isFile: (String) -> Bool = SandboxEntitlements.isExistingFile) -> (homeRelative: [String], absolute: [String]) {
        var home: [String] = []
        var absolute: [String] = []
        for case .files(let paths) in manifest.capabilities {
            for path in paths {
                let expanded = NSString(string: path).expandingTildeInPath
                let entry = isFile(expanded) || path.hasSuffix("/") ? path : path + "/"
                if path == "~" || path.hasPrefix("~/") {
                    home.append(String(entry.dropFirst()))
                } else if path.hasPrefix("/") {
                    absolute.append(entry)
                }
            }
        }
        return (home, absolute)
    }

    public static func isExistingFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    public static func propertyList(for manifest: Manifest) throws -> Data {
        var plist: [String: Any] = entitlements(for: manifest)
        let exceptions = fileExceptions(for: manifest)
        if !exceptions.homeRelative.isEmpty {
            plist["com.apple.security.temporary-exception.files.home-relative-path.read-write"] = exceptions.homeRelative
        }
        if !exceptions.absolute.isEmpty {
            plist["com.apple.security.temporary-exception.files.absolute-path.read-write"] = exceptions.absolute
        }
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    /// One line per capability, in words, for the install sheet and `fluidctl`.
    public static func summary(for manifest: Manifest) -> [String] {
        if manifest.capabilities.isEmpty {
            return ["No network, files, commands, secrets, clipboard, power or calendar."]
        }
        return manifest.capabilities.map(\.summary)
    }
}

extension Capability {
    /// The capability in words, for install and update sheets.
    public var summary: String {
        switch self {
        case .network(let hosts): return "Connects to " + (hosts.isEmpty ? "the network" : hosts.joined(separator: ", "))
        case .files(let paths): return "Reads and writes " + paths.joined(separator: ", ")
        case .run(let commands): return "Runs " + commands.joined(separator: ", ")
        case .secret(let name): return "Reads the secret \(name)"
        case .oauth(let provider):
            return "Signs in to \(provider.name) (\(URLParts.host(of: provider.authorizeURL) ?? provider.authorizeURL))" + (provider.scopes.isEmpty ? "" : " with scopes " + provider.scopes.joined(separator: " "))
        case .clipboard: return "Reads everything you copy, and pastes into the app you're using"
        case .power: return "Keeps the Mac awake, and reads battery and running apps"
        case .calendar: return "Reads your calendar events"
        }
    }

    /// The case's name as written in a manifest, for error messages.
    public var caseName: String {
        switch self {
        case .network: return "network"
        case .files: return "files"
        case .run: return "run"
        case .secret: return "secret"
        case .oauth: return "oauth"
        case .clipboard: return "clipboard"
        case .power: return "power"
        case .calendar: return "calendar"
        }
    }
}
