import Foundation
import StackbarHostCore
import StackbarProtocol

// The commands a publisher and a store use: keys, bundles, helpers, the index.

/// A publisher's private key from the file `keygen` wrote (base64). A file
/// that can't be read throws; one that isn't a key ends the command.
private func privateKey(in file: String, hint: String = "; run stackbarctl keygen") throws -> Data {
    guard let key = Data(base64Encoded: try String(contentsOfFile: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) else { fail("\(file) is not a key\(hint)") }
    return key
}

/// `helper`: prebuilt helpers, so a Mac without a compiler runs plugins.
@MainActor
func prebuiltHelper(_ rest: [String]) {
    // Prebuilt helpers (PrebuiltHelpers): what the store and the app ship so
    // a Mac without Xcode or the Command Line Tools can run plugins.
    let package = StackbarPaths.stackbarPackage()
    let builder = PluginBuilder(stackbarPackage: package, cacheRoot: flag("--cache", in: rest).map { URL(fileURLWithPath: $0) } ?? StackbarPaths.buildCache)
    switch rest.first {
    case "kit":
        guard let protocolVersion = PluginBuilder.protocolVersion(of: package) else { fail("no StackbarKit at \(package.path); set STACKBAR_PACKAGE") }
        print("\(builder.stackbarKit) \(protocolVersion)")
    case "build":
        guard rest.count >= 2, let out = flag("-o", in: rest), let keyFile = flag("--key", in: rest) else { fail(usage) }
        do {
            let key = try privateKey(in: keyFile, hint: "")
            var (binary, record) = try builder.buildHelper(source: URL(fileURLWithPath: rest[1]))
            let destination = URL(fileURLWithPath: out)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: binary, to: destination)
            record.url = flag("--url", in: rest) ?? destination.lastPathComponent
            try record.sign(privateKey: key)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(record), as: UTF8.self))
        } catch let failure as PluginBuilder.Failure {
            fail(failure.description)
        } catch {
            fail("\(error)")
        }
    case "prebuild":
        guard rest.count >= 3 else { fail(usage) }
        let directory = URL(fileURLWithPath: rest[1])
        let inputs = rest.dropFirst(2).prefix { !$0.hasPrefix("--") }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("stackbar-prebuild-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            for input in inputs {
                var source = URL(fileURLWithPath: input)
                if source.pathExtension == PluginBundle.fileExtension {
                    let bundle = try PluginBundle.decode(Data(contentsOf: source))
                    source = scratch.appendingPathComponent(PluginBuilder.sanitizedName(bundle.manifest.id) + ".swift")
                    try Data(bundle.source.utf8).write(to: source)
                }
                let (binary, record) = try builder.buildHelper(source: source)
                let file = directory.appendingPathComponent(PrebuiltHelpers.exactName(sourceDigest: record.sourceDigest, stackbarKit: record.stackbarKit))
                try? FileManager.default.removeItem(at: file)
                try FileManager.default.copyItem(at: binary, to: file)
                print("\(file.lastPathComponent)  \(record.id) \(record.version)")
            }
        } catch let failure as PluginBuilder.Failure {
            fail(failure.description)
        } catch {
            fail("\(error)")
        }
    default:
        fail(usage)
    }
}

/// `keygen`: a publisher key.
@MainActor
func keygen(_ rest: [String]) {
    let keyFile = URL(fileURLWithPath: flag("--key", in: rest) ?? StackbarPaths.dataDirectory.appendingPathComponent("publisher.key").path)
    if FileManager.default.fileExists(atPath: keyFile.path) { fail("\(keyFile.path) already exists") }
    do {
        let key = try Signing.generateKey()
        try FileManager.default.createDirectory(at: keyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try key.privateKey.base64EncodedString().write(to: keyFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFile.path)
        print("private key: \(keyFile.path)\npublic key: \(key.publicKey.base64EncodedString())")
    } catch {
        fail("\(error)")
    }
}

/// `sign`: a plugin's source and manifest as a signed bundle.
@MainActor
func sign(_ rest: [String]) {
    guard let path = rest.first, let publisher = flag("--publisher", in: rest) else { fail(usage) }
    let keyFile = flag("--key", in: rest) ?? StackbarPaths.dataDirectory.appendingPathComponent("publisher.key").path
    do {
        let key = try privateKey(in: keyFile)
        let source = try String(contentsOfFile: path, encoding: .utf8)
        let manifest = try PluginProcess.readManifest(executable: helper(for: path))
        try PluginIndex.checkPublishable(manifest)
        let bundle = try Signing.bundle(source: source, manifest: manifest, publisherName: publisher, privateKey: key)
        let out = URL(fileURLWithPath: flag("-o", in: rest) ?? (PluginBuilder.sanitizedName(manifest.id) + "." + PluginBundle.fileExtension))
        try bundle.encoded().write(to: out)
        print(out.path)
    } catch {
        fail("\(error)")
    }
}

/// `verify`: whether a bundle is whole and who signed it.
@MainActor
func verify(_ rest: [String]) {
    guard let path = rest.first else { fail(usage) }
    do {
        let bundle = try PluginBundle.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        try bundle.verify()
        print("valid: \(bundle.manifest.name) \(bundle.manifest.version) (\(bundle.manifest.id)), signed by \(bundle.publisher.name)")
        for line in SandboxEntitlements.summary(for: bundle.manifest) { print("- \(line)") }
    } catch {
        fail("\(error)")
    }
}

/// `install`: a bundle from a file, a URL or an index into the app's plugins.
@MainActor
func install(_ rest: [String]) async {
    let installer = PluginInstaller(pluginsDirectory: StackbarPaths.pluginsDirectory, publishers: PublisherStore(file: StackbarPaths.publishersFile), recordFile: StackbarPaths.dataDirectory.appendingPathComponent("installed.json"))
    do {
        let bundle: PluginBundle
        var indexURL: URL?
        if let index = flag("--index", in: rest) {
            guard let id = rest.last, id != index, let url = URL(string: index) else { fail(usage) }
            let catalog = try await PluginIndex.fetch(url)
            guard let entry = catalog.plugins.filter({ $0.id == id }).max(by: { $1.isNewer(than: $0.version) }) else { fail("\(id) is not in \(catalog.name)") }
            try catalog.checkInstallable(entry)
            bundle = try await PluginIndex.bundle(for: entry, indexURL: url)
            indexURL = url
        } else if let target = rest.first, target.hasPrefix("https://"), let url = URL(string: target) {
            bundle = try PluginBundle.decode(try await PluginIndex.download(url))
        } else if let target = rest.first {
            bundle = try PluginBundle.decode(Data(contentsOf: URL(fileURLWithPath: target)))
        } else {
            fail(usage)
        }
        // As the app does: a store's prebuilt helper, so a Mac without a
        // compiler can run the plugin (PrebuiltHelpers).
        let builder = PluginBuilder(stackbarPackage: StackbarPaths.stackbarPackage(), cacheRoot: StackbarPaths.buildCache)
        var prebuilt: PrebuiltHelpers.Download?
        if let indexURL {
            prebuilt = try await PrebuiltHelpers.prepare(bundle, indexURL: indexURL, builder: builder, toolchain: PluginBuilder.hasToolchain)
        }
        let installation = PluginInstallation(installer: installer, ledger: CapabilityLedger(file: StackbarPaths.ledgerFile), switches: PluginSwitches(),
                                              helpers: .init(directory: builder.downloadedHelpers, stackbarKit: builder.stackbarKit))
        let file = try installation.install(bundle, helper: prebuilt)
        if let prebuilt {
            note(prebuilt.exact ? "using the store's prebuilt helper" : "using the store's prebuilt helper for another StackbarKit with the same protocol")
        }
        let built = try PluginProcess.readManifest(executable: helper(for: file.path))
        try installation.confirm(built, file: file)
        print("installed \(bundle.manifest.name) \(bundle.manifest.version) to \(file.path)")
        for line in SandboxEntitlements.summary(for: bundle.manifest) { print("- \(line)") }
        print("Stackbar asks you to approve these the first time it runs the plugin.")
    } catch {
        fail("\(error)")
    }
}

/// `index`: builds, verifies, searches and fetches from a store's index.
@MainActor
func index(_ rest: [String]) async {
    guard rest.count >= 2 else { fail(usage) }
    do {
        switch rest[0] {
        case "build":
            let directory = URL(fileURLWithPath: rest[1])
            let revoked = try flag("--revoked", in: rest).map { try JSONDecoder().decode([PluginIndex.Revocation].self, from: Data(contentsOf: URL(fileURLWithPath: $0))) }
            var index = try PluginIndex.build(name: flag("--name", in: rest) ?? directory.lastPathComponent, root: directory, homepage: flag("--homepage", in: rest), revoked: revoked)
            if let keyFile = flag("--key", in: rest) {
                let key = try privateKey(in: keyFile)
                index = try index.signed(privateKey: key)
            }
            let out = directory.appendingPathComponent("index.json")
            try index.encoded().write(to: out)
            print("\(out.path): \(index.plugins.count) plugins" + (index.signature == nil ? ", unsigned" : ", signed"))
        case "verify":
            guard let key = flag("--public-key", in: rest) else { fail(usage) }
            let url = rest[1].hasPrefix("https://") ? URL(string: rest[1]) : URL(fileURLWithPath: rest[1])
            guard let url else { fail(usage) }
            let index = try await PluginIndex.fetch(url, publicKey: key)
            print("valid: \(index.name), \(index.plugins.count) plugins, \(index.revoked?.count ?? 0) revoked")
        case "fetch":
            let directory = URL(fileURLWithPath: rest[1])
            let key = flag("--public-key", in: rest) ?? OfficialIndex.publicKey
            guard let url = URL(string: flag("--index", in: rest) ?? OfficialIndex.url.absoluteString) else { fail(usage) }
            let index = try await PluginIndex.fetch(url, publicKey: key)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var fetched = 0
            for id in BundledStore.pluginIDs.sorted() {
                guard let entry = index.plugins.filter({ $0.id == id && $0.requiredStackbar() == nil }).max(by: { $1.isNewer(than: $0.version) }) else {
                    print("not in \(index.name) for Stackbar \(StackbarVersion.current): \(id)")
                    continue
                }
                try index.checkInstallable(entry)
                let bundle = try await PluginIndex.bundle(for: entry, indexURL: url)
                try bundle.verify()
                guard bundle.publisher.publicKey == key else { fail("\(id) is not signed by the index's key") }
                try bundle.encoded().write(to: directory.appendingPathComponent("\(id)-\(bundle.manifest.version).\(PluginBundle.fileExtension)"))
                print("fetched \(bundle.manifest.name) \(bundle.manifest.version)")
                fetched += 1
            }
            print("\(directory.path): \(fetched) bundles")
        case "search":
            guard let url = URL(string: rest[1]) else { fail(usage) }
            let index = try await PluginIndex.fetch(url, publicKey: flag("--public-key", in: rest))
            let query = rest.count > 2 && !rest[2].hasPrefix("--") ? rest[2] : ""
            for entry in index.search(query) {
                let needs = entry.requiredStackbar().map { " (needs Stackbar \($0))" } ?? ""
            print("\(entry.id)  \(entry.name) \(entry.version) by \(entry.publisher)\(needs)" + (entry.summary.map { " — \($0)" } ?? ""))
            }
        default:
            fail(usage)
        }
    } catch {
        fail("\(error)")
    }
}
