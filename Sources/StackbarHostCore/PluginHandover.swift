import Foundation
import StackbarProtocol

/// Hands a plugin over to the one that `replaces` it: two plugins merged into
/// one, or one renamed.
///
/// The first time the new plugin reports its commands, the user's aliases,
/// hotkeys and command switches, palette usage and favourites move from the
/// old plugin's commands to the new plugin's commands with the same ids (and
/// titles). Each handover
/// happens once and is remembered, so turning the old plugin back on later
/// doesn't hand it over again. What happens to the old plugin itself (turned
/// off, offered for uninstall) is the app's part.
public final class PluginHandover: @unchecked Sendable {
    public struct Record: Codable, Equatable, Sendable {
        /// The plugin that was replaced.
        public var from: String
        /// The plugin that took it over.
        public var to: String
        public var at: Date
    }

    private let file: URL?
    private let lock = NSLock()
    private var records: [Record] = []

    public init(file: URL?) {
        self.file = file
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let file, let data = try? Data(contentsOf: file), let decoded = try? decoder.decode([Record].self, from: data) {
            records = decoded
        }
    }

    public var all: [Record] { lock.withLock { records } }

    /// The plugins `manifest` replaces that haven't been handed over to it yet.
    public func pending(for manifest: Manifest) -> [String] {
        let done = lock.withLock { Set(records.filter { $0.to == manifest.id }.map(\.from)) }
        var seen = Set<String>()
        return (manifest.replaces ?? []).filter { $0 != manifest.id && !done.contains($0) && seen.insert($0).inserted }
    }

    /// The plugin that took `pluginID` over, if one did.
    public func replacement(of pluginID: String) -> String? {
        lock.withLock { records.last { $0.from == pluginID }?.to }
    }

    /// Moves what the user set up for plugin `from`'s commands to plugin
    /// `to`, and remembers it. Returns the commands whose preferences moved.
    ///
    /// Only commands `to` declares with the same id carry over (`commands`,
    /// id → title). Where the old command's title is known (`oldTitles`) and
    /// differs, the two only share an id by chance (two plugins that each had
    /// a "restore"), so that one stays behind.
    @discardableResult
    public func hand(from: String, to: String, commands: [String: String], oldTitles: [String: String] = [:],
                     preferences: CommandPreferences, memory: PaletteMemory? = nil,
                     now: Date = Date()) -> [CommandKey] {
        let carries = { (id: String) -> Bool in
            guard let title = commands[id] else { return false }
            guard let old = oldTitles[id] else { return true }
            return old.caseInsensitiveCompare(title) == .orderedSame
        }
        let moved = preferences.move(pluginID: from, to: to, carries: carries)
        memory?.handOver(from: from, to: to, carries: carries)
        lock.withLock {
            records.removeAll { $0.from == from && $0.to == to }
            records.append(Record(from: from, to: to, at: now))
        }
        save()
        return moved
    }

    private func save() {
        guard let file else { return }
        let snapshot = all
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }
}
