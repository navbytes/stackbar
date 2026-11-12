import Foundation
import StackbarProtocol

/// Plugin rows the palette keeps past the text that found them: rows you
/// pinned, and rows you open often (apps). Each is a snapshot to draw and
/// the text that finds the row again, since a root-search row only exists
/// while its plugin answers what is typed.
public final class PaletteRememberedRows: @unchecked Sendable {
    public struct Row: Codable, Equatable, Sendable {
        public var pluginID: String
        public var pluginName: String
        public var commandID: String
        public var rowKey: String
        public var title: String
        public var subtitle: String?
        public var symbol: String?
        public var appIcon: String?
        public var fileIcon: String?
        /// What is sent to the command to find the row again.
        public var query: String

        public init(pluginID: String, pluginName: String, commandID: String, rowKey: String, title: String, subtitle: String? = nil,
                    symbol: String? = nil, appIcon: String? = nil, fileIcon: String? = nil, query: String) {
            self.pluginID = pluginID
            self.pluginName = pluginName
            self.commandID = commandID
            self.rowKey = rowKey
            self.title = title
            self.subtitle = subtitle
            self.symbol = symbol
            self.appIcon = appIcon
            self.fileIcon = fileIcon
            self.query = query
        }

        /// The id its use and pin are kept under: the live row's `rankKey`.
        public var id: String { PaletteIndex.Entry.rowID(pluginID: pluginID, commandID: commandID, rowKey: rowKey) }

        public var entry: PaletteIndex.Entry {
            var entry = PaletteIndex.Entry(pluginID: pluginID, pluginName: pluginName, title: title, subtitle: subtitle, symbol: symbol,
                                           kind: .remembered(command: commandID, rowKey: rowKey, query: query))
            entry.appIcon = appIcon
            entry.fileIcon = fileIcon
            return entry
        }
    }

    /// Rows kept, at most; the least recently remembered go first.
    public static let limit = 300

    private let file: URL?
    private let lock = NSLock()
    private var stored: [Row] = []

    public init(file: URL?) {
        self.file = file
        stored = JSONFile.read(from: file) ?? []
    }

    public var all: [Row] { lock.withLock { stored } }

    public func row(_ id: String) -> Row? { lock.withLock { stored.first { $0.id == id } } }

    /// Keeps the newest snapshot of the row, last in line to be dropped.
    /// `keeping` are ids never dropped for room (the pinned ones).
    public func remember(_ row: Row, keeping: Set<String> = []) {
        lock.withLock {
            stored.removeAll { $0.id == row.id }
            stored.append(row)
            while stored.count > Self.limit, let index = stored.firstIndex(where: { !keeping.contains($0.id) }) {
                stored.remove(at: index)
            }
        }
        save()
    }

    /// Carries plugin `from`'s rows over to plugin `to` (a handover).
    public func move(pluginID from: String, to: String, carries: (String) -> Bool = { _ in true }) {
        lock.withLock {
            stored = stored.map { row in
                guard row.pluginID == from, carries(row.commandID) else { return row }
                var moved = row
                moved.pluginID = to
                return moved
            }
        }
        save()
    }

    private func save() {
        guard let file else { return }
        try? JSONFile.write(all, to: file)
    }
}
