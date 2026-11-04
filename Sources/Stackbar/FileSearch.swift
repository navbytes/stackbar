#if os(macOS)
import AppKit
import StackbarHostCore

/// Files by name from Spotlight's index, for the palette: most recently
/// used first, a few at a time, searched a moment after typing stops.
@MainActor
final class FileSearch {
    static let shared = FileSearch()

    /// The query `results` answer.
    private(set) var text = ""
    private(set) var results: [PaletteIndex.Entry] = []
    /// Called when new results land.
    var onChange: (@MainActor () -> Void)?

    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?
    private var pending: Task<Void, Never>?
    private static let limit = 5
    private static let minimumLength = 3

    /// Searches for `text` after a short pause; shorter queries clear.
    func search(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard text != self.text else { return }
        pending?.cancel()
        stop()
        self.text = text
        if !results.isEmpty {
            results = []
            onChange?()
        }
        guard text.count >= Self.minimumLength else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self?.start(text)
        }
    }

    func cancel() {
        pending?.cancel()
        stop()
        text = ""
        results = []
    }

    private func start(_ text: String) {
        let query = NSMetadataQuery()
        // Every word somewhere in the name, case and accents ignored.
        let words = text.split(separator: " ").map { NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, "*\($0)*") }
        query.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: words)
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]
        observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(text) }
        }
        self.query = query
        query.start()
    }

    private func finish(_ text: String) {
        guard let query, text == self.text else { return }
        query.disableUpdates()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var found: [PaletteIndex.Entry] = []
        // Look a little past the limit: some hits are skipped (bundles,
        // Library, hidden files).
        for index in 0..<min(query.resultCount, 60) where found.count < Self.limit {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  let entry = PaletteFiles.entry(path: path, home: home) else { continue }
            found.append(entry)
        }
        stop()
        results = found
        onChange?()
    }

    private func stop() {
        query?.stop()
        query = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }
}
#endif
