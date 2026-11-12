import Foundation
import StackbarHostCore
import StackbarProtocol

// The commands about this Mac's Stackbar: its log, health, setup and secrets.

/// `logs`: the end of the host log.
@MainActor
func logs(_ rest: [String]) {
    let count = flag("-n", in: rest).flatMap(Int.init) ?? 100
    print("\(HostLog.shared.file.path)\n")
    for line in HostLog.shared.tail(count) { print(line) }
}

/// `doctor`: the toolchain, StackbarKit and the data folders.
@MainActor
func doctor() -> Never {
    var healthy = true
    func check(_ name: String, _ problem: String?) {
        if let problem {
            healthy = false
            print("✗ \(name): \(problem)")
        } else {
            print("✓ \(name)")
        }
    }
    if PluginBuilder.hasToolchain {
        check("Swift toolchain", PluginBuilder.toolchainProblem())
    } else {
        // Not a failure: store plugins run prebuilt. Only writing or changing
        // a plugin needs a compiler.
        print("! Swift toolchain: \(PluginBuilder.toolchainProblem() ?? "not installed")")
    }
    let package = StackbarPaths.stackbarPackage()
    check("StackbarKit at \(package.path)", FileManager.default.fileExists(atPath: package.appendingPathComponent("Package.swift").path) ? nil : "no Package.swift there; set STACKBAR_PACKAGE")
    for directory in [StackbarPaths.dataDirectory, StackbarPaths.cacheDirectory] {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        check("writable \(directory.path)", FileManager.default.isWritableFile(atPath: directory.path) ? nil : "not writable")
    }
    exit(healthy ? 0 : 1)
}

/// `settings`: the app's setup to a file and back.
@MainActor
func settings(_ rest: [String]) {
    guard rest.count >= 2 else { fail(usage) }
    // The app's own preferences domain, so the CLI reads and writes what it does.
    let appDefaults = UserDefaults(suiteName: "io.navbytes.stackbar") ?? .standard
    let file = URL(fileURLWithPath: rest[1])
    do {
        switch rest[0] {
        case "export":
            var parts = Set(SettingsArchive.Part.allCases)
            if let index = rest.firstIndex(of: "--only") {
                guard rest.indices.contains(index + 1), let chosen = SettingsArchive.Part.parse(rest[index + 1]) else {
                    fail("--only takes a list of: " + SettingsArchive.Part.allCases.map(\.rawValue).joined(separator: ","))
                }
                parts = chosen
            }
            let archive = try SettingsArchive.export(dataDirectory: StackbarPaths.dataDirectory, defaults: appDefaults, parts: parts)
            try archive.encoded().write(to: file, options: .atomic)
            let summary = archive.summary
            print("wrote \(file.path): \(summary.pluginFiles.count) plugin files, \(summary.savedValues) saved values, \(summary.preferences) preferences")
        case "import":
            let archive = try SettingsArchive.decode(Data(contentsOf: file))
            try archive.apply(to: StackbarPaths.dataDirectory, defaults: appDefaults, replacing: rest.contains("--replace"))
            print("imported \(file.lastPathComponent) (\(rest.contains("--replace") ? "replaced" : "merged")); open Stackbar to load it")
        default:
            fail(usage)
        }
    } catch {
        fail("\(error)")
    }
}

/// `secret`: the secrets plugins read here.
@MainActor
func secret(_ rest: [String]) {
    guard rest.count >= 2 else { fail(usage) }
    let store = StackbarPaths.defaultSecrets()
    do {
        switch rest[0] {
        case "set":
            let secretValue = rest.count > 2 ? rest[2] : (readLine(strippingNewline: true) ?? "")
            try store.setSecret(secretValue, for: rest[1])
            print("saved \(rest[1])")
        case "get":
            print(try store.secret(rest[1]) ?? "")
        case "delete":
            try store.setSecret(nil, for: rest[1])
            print("deleted \(rest[1])")
        default:
            fail(usage)
        }
    } catch {
        fail("\(error)")
    }
}
