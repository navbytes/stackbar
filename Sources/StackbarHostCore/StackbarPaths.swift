import Foundation

/// Where Stackbar keeps things, shared by the app and `stackbarctl` so both see the
/// same plugins, saved values, secrets and build cache.
///
/// macOS: `~/Library/Application Support/Stackbar` and `~/Library/Caches/Stackbar`.
/// Elsewhere: `$XDG_DATA_HOME/stackbar` and `$XDG_CACHE_HOME/stackbar`. `STACKBAR_HOME`
/// moves both, for tests and side-by-side installs.
public enum StackbarPaths {
    public static var dataDirectory: URL {
        let environment = ProcessInfo.processInfo.environment
        if let home = environment["STACKBAR_HOME"] { return URL(fileURLWithPath: home, isDirectory: true) }
        #if os(macOS)
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Stackbar", isDirectory: true)
        #else
        let base = environment["XDG_DATA_HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share")
        return base.appendingPathComponent("stackbar", isDirectory: true)
        #endif
    }

    public static var cacheDirectory: URL {
        let environment = ProcessInfo.processInfo.environment
        if let home = environment["STACKBAR_HOME"] { return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Caches", isDirectory: true) }
        #if os(macOS)
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Stackbar", isDirectory: true)
        #else
        let base = environment["XDG_CACHE_HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache")
        return base.appendingPathComponent("stackbar", isDirectory: true)
        #endif
    }

    public static var pluginsDirectory: URL { dataDirectory.appendingPathComponent("Plugins", isDirectory: true) }
    public static var storageDirectory: URL { dataDirectory.appendingPathComponent("Storage", isDirectory: true) }
    public static var buildCache: URL { cacheDirectory.appendingPathComponent("builds", isDirectory: true) }
    public static var ledgerFile: URL { dataDirectory.appendingPathComponent("approvals.json") }
    public static var publishersFile: URL { dataDirectory.appendingPathComponent("publishers.json") }
    public static var agentSocket: URL { dataDirectory.appendingPathComponent("agent.sock") }
    /// The host log. macOS: `~/Library/Logs/Stackbar/stackbar.log`.
    public static var logFile: URL {
        #if os(macOS)
        if ProcessInfo.processInfo.environment["STACKBAR_HOME"] == nil {
            return FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Stackbar/stackbar.log")
        }
        #endif
        return dataDirectory.appendingPathComponent("Logs/stackbar.log")
    }
    /// Held by the running app; see `InstanceLock`.
    public static var instanceLockFile: URL { dataDirectory.appendingPathComponent("stackbar.lock") }
    public static var widgetSnapshots: URL { dataDirectory.appendingPathComponent("Widgets", isDirectory: true) }

    /// The Keychain on macOS (shared with the app), a 0600 file elsewhere.
    /// `stackbarctl` also reads environment variables as a fallback, so
    /// `GITHUB_TOKEN=… stackbarctl render` works; the app does not, because a
    /// plugin could then declare any variable of the app's environment (an
    /// `AWS_SECRET_ACCESS_KEY` inherited from the shell that ran it) as a
    /// secret and read it without the user ever entering it.
    public static func defaultSecrets(includeEnvironment: Bool = true) -> any SecretStore {
        #if canImport(Security)
        let primary: any SecretStore = KeychainSecretStore()
        #else
        let primary: any SecretStore = FileSecretStore(file: dataDirectory.appendingPathComponent("secrets.json"))
        #endif
        return ChainedSecretStore(includeEnvironment ? [primary, EnvironmentSecretStore()] : [primary])
    }

    /// Moves a Mac's data from before the rename (the app was called Fluid
    /// until November 2026): `~/Library/Application Support/Fluid` and
    /// `~/Library/Logs/Fluid` become their Stackbar folders, once, and only
    /// when the Stackbar folder doesn't exist yet. The build cache is not
    /// moved; plugins rebuild against StackbarKit anyway. Keychain secrets
    /// are under a new service and have to be entered again.
    public static func migrateFromFluid() {
        #if os(macOS)
        guard ProcessInfo.processInfo.environment["STACKBAR_HOME"] == nil else { return }
        let fileManager = FileManager.default
        let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        for folder in ["Application Support", "Logs"] {
            let old = library.appendingPathComponent("\(folder)/Fluid", isDirectory: true)
            let new = library.appendingPathComponent("\(folder)/Stackbar", isDirectory: true)
            guard fileManager.fileExists(atPath: old.path), !fileManager.fileExists(atPath: new.path) else { continue }
            try? fileManager.moveItem(at: old, to: new)
        }
        let log = library.appendingPathComponent("Logs/Stackbar/fluid.log")
        if fileManager.fileExists(atPath: log.path) {
            try? fileManager.moveItem(at: log, to: logFile.deletingLastPathComponent().appendingPathComponent("fluid-before-rename.log"))
        }
        #endif
    }

    /// The package that provides StackbarKit to plugin builds: `STACKBAR_PACKAGE`,
    /// then a copy bundled next to the running executable
    /// (`../Resources/StackbarKit` in an app bundle), then the source checkout this
    /// binary was built from.
    public static func stackbarPackage(sourceFile: String = #filePath) -> URL {
        if let override = ProcessInfo.processInfo.environment["STACKBAR_PACKAGE"] {
            return URL(fileURLWithPath: override)
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let bundled = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/StackbarKit", isDirectory: true)
        if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("Package.swift").path) {
            return bundled
        }
        // Sources/StackbarHostCore/StackbarPaths.swift → the package root.
        return URL(fileURLWithPath: sourceFile).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
