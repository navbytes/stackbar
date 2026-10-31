import Foundation
import FluidProtocol
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Compiles single-file Swift plugins into helper executables.
///
/// All plugins share one generated SwiftPM workspace in the build cache, one
/// executable target per plugin version, so FluidKit is compiled once and
/// every later plugin build only compiles the plugin itself (seconds, not
/// tens of seconds). Targets are named after a hash of the source, so an
/// unchanged plugin is never rebuilt, and the least recently built targets are
/// pruned. A failed build returns the compiler's diagnostics mapped back to the
/// plugin's own file: the loop an AI author needs.
///
/// Builds are serialized: within a process by a lock, across processes (the
/// app and `fluidctl`) by an advisory file lock on the workspace.
public struct PluginBuilder: Sendable {
    public struct Output: Sendable {
        public var binary: URL
        public var cached: Bool
    }

    public struct Failure: Error, CustomStringConvertible, Sendable {
        public var diagnostics: [BuildDiagnostic]
        public var log: String

        public var description: String {
            diagnostics.isEmpty ? log : diagnostics.map(\.description).joined(separator: "\n")
        }
    }

    /// The Fluid package (the directory holding Package.swift with FluidKit).
    public var fluidPackage: URL
    public var cacheRoot: URL
    public var configuration: String
    /// How many plugin versions the workspace keeps before pruning.
    public var keepTargets = 64
    /// How long one build may take.
    public var timeout: Double = 600

    private static let lock = NSLock()

    public init(fluidPackage: URL, cacheRoot: URL, configuration: String = "release") {
        self.fluidPackage = fluidPackage
        self.cacheRoot = cacheRoot
        self.configuration = configuration
    }

    var workspace: URL { cacheRoot.appendingPathComponent("workspace", isDirectory: true) }

    public func build(source: URL) throws -> Output {
        let code = try Data(contentsOf: source)
        // The key covers FluidKit too: after an update of Fluid, a plugin
        // built against the old FluidKit must be rebuilt, not reused.
        let key = Self.cacheKey(code + Data("\(configuration)|\(fluidPackage.path)|\(Self.frameworkDigest(fluidPackage))".utf8))
        let target = Self.targetName(source.deletingPathExtension().lastPathComponent, key: key)
        let binary = workspace.appendingPathComponent(".build/\(configuration)/\(target)")
        let sourcesDir = workspace.appendingPathComponent("Sources/\(target)", isDirectory: true)

        if FileManager.default.isExecutableFile(atPath: binary.path) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: sourcesDir.path)
            return Output(binary: binary, cached: true)
        }

        Self.lock.lock()
        defer { Self.lock.unlock() }
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        let fileLock = try FileLock(workspace.appendingPathComponent(".fluid-build.lock"))
        defer { fileLock.unlock() }
        // Another process may have built it while we waited for the lock.
        if FileManager.default.isExecutableFile(atPath: binary.path) {
            return Output(binary: binary, cached: true)
        }

        let copied = sourcesDir.appendingPathComponent("Plugin.swift")
        try code.write(to: copied)
        let targets = try pruneAndList(keeping: target)
        try Self.manifest(fluidPackage: fluidPackage, targets: targets).write(to: workspace.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let (status, log) = try Self.run(Self.swift + ["build", "-c", configuration, "--package-path", workspace.path, "--product", target], timeout: timeout)
        guard status == 0, FileManager.default.isExecutableFile(atPath: binary.path) else {
            let diagnostics = Self.parseDiagnostics(log).compactMap { diagnostic -> BuildDiagnostic? in
                var mapped = diagnostic
                if diagnostic.file.hasSuffix("Sources/\(target)/Plugin.swift") {
                    mapped.file = source.path
                } else if diagnostic.file.contains("/Sources/") && diagnostic.file.hasSuffix("/Plugin.swift") {
                    return nil // another plugin's target; not this build's problem
                }
                return mapped
            }
            throw Failure(diagnostics: diagnostics, log: Self.trimmed(log))
        }
        return Output(binary: binary, cached: false)
    }

    /// Removes the least recently used plugin targets beyond `keepTargets`
    /// and returns the targets that remain.
    private func pruneAndList(keeping current: String) throws -> [String] {
        let sources = workspace.appendingPathComponent("Sources", isDirectory: true)
        let entries = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: [.contentModificationDateKey])
        let dated = entries.map { url -> (String, Date) in
            (url.lastPathComponent, (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }.sorted { $0.1 > $1.1 }
        var keep: [String] = []
        for (name, _) in dated {
            if name == current || keep.count < keepTargets - 1 {
                keep.append(name)
            } else {
                try? FileManager.default.removeItem(at: sources.appendingPathComponent(name))
                try? FileManager.default.removeItem(at: workspace.appendingPathComponent(".build/\(configuration)/\(name)"))
            }
        }
        if !keep.contains(current) { keep.append(current) }
        return keep.sorted()
    }

    static func manifest(fluidPackage: URL, targets: [String]) -> String {
        let path = fluidPackage.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        // SwiftPM names a path dependency after its folder, whatever the
        // package calls itself.
        let identity = fluidPackage.standardizedFileURL.lastPathComponent.lowercased()
        let lines = targets.map { target in
            "        .executableTarget(name: \"\(target)\", dependencies: [.product(name: \"FluidKit\", package: \"\(identity)\")], path: \"Sources/\(target)\"),"
        }
        return """
        // swift-tools-version: 6.2
        // Generated by Fluid: one target per plugin version. Edit the plugins'
        // own .swift files, not this one.
        import PackageDescription

        let package = Package(
            name: "FluidPlugins",
            platforms: [.macOS("26.0")],
            dependencies: [.package(path: "\(path)")],
            targets: [
        \(lines.joined(separator: "\n"))
            ]
        )

        """
    }

    /// A valid, readable module name: `Clock_1a2b3c…`.
    static func targetName(_ name: String, key: String) -> String {
        let letters = name.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
        var base = String(String.UnicodeScalarView(letters)).prefix(40)
        if base.isEmpty || base.first!.isNumber { base = "Plugin" + base }
        return "\(base)_\(key)"
    }

    /// The Swift driver: `FLUID_SWIFT`, else `swift` from the PATH (on macOS
    /// /usr/bin/swift is Xcode's shim, there even for apps opened from Finder).
    static var swift: [String] {
        if let custom = ProcessInfo.processInfo.environment["FLUID_SWIFT"], !custom.isEmpty { return [custom] }
        return ["swift"]
    }

    /// Whether a Swift toolchain is installed, in words when it isn't.
    public static func toolchainProblem() -> String? {
        guard let (status, output) = try? run(swift + ["--version"], timeout: 30), status == 0 else {
            #if os(macOS)
            return "Fluid builds plugins with Swift. Install Xcode, or the Command Line Tools with: xcode-select --install"
            #else
            return "Fluid builds plugins with Swift 6.2 or later; install it from swift.org and put swift on the PATH (or set FLUID_SWIFT)."
            #endif
        }
        return output.contains("Swift version 6") ? nil : "Fluid needs Swift 6.2 or later; found: \(output.split(separator: "\n").first ?? "")"
    }

    /// Keeps the end of a long build log, where the errors are.
    static func trimmed(_ log: String, limit: Int = 8000) -> String {
        log.count <= limit ? log : "…\n" + String(log.suffix(limit))
    }

    /// Compiler output lines of the form `file:line:col: error: message`.
    public static func parseDiagnostics(_ log: String) -> [BuildDiagnostic] {
        var seen = Set<String>()
        var result: [BuildDiagnostic] = []
        for line in log.split(whereSeparator: \.isNewline) {
            for severity in BuildDiagnostic.Severity.allCases {
                let marker = ": \(severity.rawValue): "
                guard let range = line.range(of: marker) else { continue }
                let location = line[..<range.lowerBound].split(separator: ":")
                guard location.count >= 3, let lineNumber = Int(location[location.count - 2]), let column = Int(location[location.count - 1]) else { continue }
                let file = location.dropLast(2).joined(separator: ":")
                let diagnostic = BuildDiagnostic(file: file, line: lineNumber, column: column, severity: severity, message: String(line[range.upperBound...]))
                if seen.insert(diagnostic.description).inserted { result.append(diagnostic) }
            }
        }
        return result
    }

    /// SHA-256, first 128 bits in hex. A cached binary is run for any source
    /// with the same key, so the key has to be collision-resistant: with a
    /// weak hash, a signed bundle could be crafted to match the key of a
    /// different, already built plugin and run that one instead.
    static func cacheKey(_ data: Data) -> String {
        String(SHA256.hex(data).prefix(32))
    }

    /// A digest of the FluidKit and FluidProtocol sources plugins compile
    /// against (the package's `Sources/FluidKit` and `Sources/FluidProtocol`).
    static func frameworkDigest(_ fluidPackage: URL) -> String {
        var data = Data()
        for module in ["FluidKit", "FluidProtocol"] {
            let folder = fluidPackage.appendingPathComponent("Sources/\(module)", isDirectory: true)
            let files = (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
                .filter { $0.pathExtension == "swift" }
                .sorted { $0.path < $1.path }
            for file in files {
                data.append(Data(file.lastPathComponent.utf8))
                data.append((try? Data(contentsOf: file)) ?? Data())
            }
        }
        return SHA256.hex(data)
    }

    public static func sanitizedName(_ name: String) -> String {
        let allowed = name.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" ? Character($0) : "-" }
        let result = String(allowed)
        return result.isEmpty ? "plugin" : result
    }

    /// A file name for per-plugin data (storage, widget snapshots) that is
    /// unique per id. `sanitizedName` maps `dev.a-b.c` and `dev-a.b.c` to the
    /// same name, which would let two plugins share one storage file; here
    /// letters, digits, `-` and `.` stay and every other byte becomes `_XX`.
    public static func dataFileName(_ pluginID: String) -> String {
        var result = ""
        for (index, byte) in pluginID.utf8.enumerated() {
            let scalar = Unicode.Scalar(byte)
            let plain = byte < 0x80 && (CharacterSet.alphanumerics.contains(scalar) || byte == UInt8(ascii: "-") || (byte == UInt8(ascii: ".") && index > 0))
            result += plain ? String(Character(scalar)) : String(format: "_%02X", byte)
        }
        return result.isEmpty ? "_" : result
    }

    static func run(_ arguments: [String], timeout: Double = 600) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        let path = environment["PATH"] ?? ""
        if !path.split(separator: ":").contains("/usr/bin") { environment["PATH"] = path.isEmpty ? "/usr/bin:/bin" : path + ":/usr/bin:/bin" }
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        let collected = OutputCollector()
        let reader = Thread {
            collected.data = output.fileHandleForReading.readDataToEndOfFile()
            collected.done.signal()
        }
        reader.start()
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = exited.wait(timeout: .now() + 5)
            _ = collected.done.wait(timeout: .now() + 5)
            return (-1, String(decoding: collected.data, as: UTF8.self) + "\nbuild timed out after \(Int(timeout))s")
        }
        _ = collected.done.wait(timeout: .now() + 30)
        return (process.terminationStatus, String(decoding: collected.data, as: UTF8.self))
    }

    #if os(macOS)
    /// Signs a copy of the helper ad hoc with App Sandbox entitlements
    /// generated from its manifest, and returns the copy to launch.
    ///
    /// `SandboxTests` checks on a Mac that a helper signed this way can't read
    /// the user's files or open connections beyond its manifest. The app
    /// signs every plugin unless `FLUID_SANDBOX=0`.
    ///
    /// The copy lives in `Sandboxed/` in the build cache, one per plugin id,
    /// and is replaced by a rename rather than re-signed in place: macOS
    /// caches a binary's signature, and rewriting a signed file that is
    /// running (a reload) can get the next launch killed. An unchanged binary
    /// with unchanged entitlements is not signed again.
    public func sign(binary: URL, manifest: Manifest) throws -> URL {
        let folder = cacheRoot.appendingPathComponent("Sandboxed", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = Self.dataFileName(manifest.id)
        let signed = folder.appendingPathComponent(name)
        let stampFile = folder.appendingPathComponent(name + ".stamp")
        let entitlements = try SandboxEntitlements.propertyList(for: manifest)
        let attributes = try FileManager.default.attributesOfItem(atPath: binary.path)
        let stamp = Data("\(binary.path)|\((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)|\((attributes[.size] as? NSNumber)?.intValue ?? 0)|\(SHA256.hex(entitlements))".utf8)
        if FileManager.default.isExecutableFile(atPath: signed.path), (try? Data(contentsOf: stampFile)) == stamp {
            return signed
        }
        let temporary = folder.appendingPathComponent("\(name).\(UUID().uuidString)")
        let entitlementsFile = folder.appendingPathComponent("\(name).entitlements")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.copyItem(at: binary, to: temporary)
        try entitlements.write(to: entitlementsFile)
        let (status, log) = try Self.run(["codesign", "--force", "--sign", "-", "--identifier", manifest.id, "--entitlements", entitlementsFile.path, temporary.path])
        if status != 0 { throw Failure(diagnostics: [], log: log) }
        guard rename(temporary.path, signed.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        try stamp.write(to: stampFile)
        return signed
    }
    #endif
}

final class OutputCollector: @unchecked Sendable {
    var data = Data()
    let done = DispatchSemaphore(value: 0)
}

/// An exclusive advisory lock on a file, held until `unlock()`.
final class FileLock {
    private let fd: Int32

    init(_ url: URL) throws {
        fd = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        flock(fd, LOCK_EX)
    }

    func unlock() {
        flock(fd, LOCK_UN)
        close(fd)
    }
}

public struct BuildDiagnostic: Equatable, Sendable, CustomStringConvertible {
    public enum Severity: String, Sendable, CaseIterable {
        case error, warning
    }

    public var file: String
    public var line: Int
    public var column: Int
    public var severity: Severity
    public var message: String

    public var description: String { "\(file):\(line):\(column): \(severity.rawValue): \(message)" }
}
