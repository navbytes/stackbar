import Foundation

/// Where Fluid keeps things, shared by the app and `fluidctl` so both see the
/// same plugins, saved values, secrets and build cache.
///
/// macOS: `~/Library/Application Support/Fluid` and `~/Library/Caches/Fluid`.
/// Elsewhere: `$XDG_DATA_HOME/fluid` and `$XDG_CACHE_HOME/fluid`. `FLUID_HOME`
/// moves both, for tests and side-by-side installs.
public enum FluidPaths {
    public static var dataDirectory: URL {
        let environment = ProcessInfo.processInfo.environment
        if let home = environment["FLUID_HOME"] { return URL(fileURLWithPath: home, isDirectory: true) }
        #if os(macOS)
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Fluid", isDirectory: true)
        #else
        let base = environment["XDG_DATA_HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share")
        return base.appendingPathComponent("fluid", isDirectory: true)
        #endif
    }

    public static var cacheDirectory: URL {
        let environment = ProcessInfo.processInfo.environment
        if let home = environment["FLUID_HOME"] { return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Caches", isDirectory: true) }
        #if os(macOS)
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Fluid", isDirectory: true)
        #else
        let base = environment["XDG_CACHE_HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache")
        return base.appendingPathComponent("fluid", isDirectory: true)
        #endif
    }

    public static var pluginsDirectory: URL { dataDirectory.appendingPathComponent("Plugins", isDirectory: true) }
    public static var storageDirectory: URL { dataDirectory.appendingPathComponent("Storage", isDirectory: true) }
    public static var buildCache: URL { cacheDirectory.appendingPathComponent("builds", isDirectory: true) }
    public static var ledgerFile: URL { dataDirectory.appendingPathComponent("approvals.json") }
    public static var publishersFile: URL { dataDirectory.appendingPathComponent("publishers.json") }
    public static var agentSocket: URL { dataDirectory.appendingPathComponent("agent.sock") }
    /// The host log. macOS: `~/Library/Logs/Fluid/fluid.log`.
    public static var logFile: URL {
        #if os(macOS)
        if ProcessInfo.processInfo.environment["FLUID_HOME"] == nil {
            return FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Fluid/fluid.log")
        }
        #endif
        return dataDirectory.appendingPathComponent("Logs/fluid.log")
    }
    public static var widgetSnapshots: URL { dataDirectory.appendingPathComponent("Widgets", isDirectory: true) }

    /// The Keychain on macOS (shared with the app), a 0600 file elsewhere;
    /// environment variables are read as a fallback either way.
    public static func defaultSecrets() -> any SecretStore {
        #if canImport(Security)
        return ChainedSecretStore([KeychainSecretStore(), EnvironmentSecretStore()])
        #else
        return ChainedSecretStore([FileSecretStore(file: dataDirectory.appendingPathComponent("secrets.json")), EnvironmentSecretStore()])
        #endif
    }

    /// The package that provides FluidKit to plugin builds: `FLUID_PACKAGE`,
    /// then a copy bundled next to the running executable
    /// (`../Resources/FluidKit` in an app bundle), then the source checkout this
    /// binary was built from.
    public static func fluidPackage(sourceFile: String = #filePath) -> URL {
        if let override = ProcessInfo.processInfo.environment["FLUID_PACKAGE"] {
            return URL(fileURLWithPath: override)
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let bundled = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/FluidKit", isDirectory: true)
        if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("Package.swift").path) {
            return bundled
        }
        // Sources/FluidHostCore/FluidPaths.swift → the package root.
        return URL(fileURLWithPath: sourceFile).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
