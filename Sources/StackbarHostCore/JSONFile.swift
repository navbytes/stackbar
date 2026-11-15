import Foundation

/// A small JSON file the host keeps: read whole, written whole. Every store
/// that saves its state this way (approvals, preferences, the palette's
/// memory, install records) reads and writes through here, so they all treat
/// a missing folder, a damaged file and a half-written one alike.
enum JSONFile {
    /// The file's value, or nil when there is no file, it can't be read or
    /// it isn't this type. A store then starts empty.
    ///
    /// A file that is there but can't be decoded (damaged, or written by a
    /// newer Stackbar before going back to an older one) is moved aside to
    /// `<name>.corrupt-<seconds>` first, as `StorageStore` does, so the
    /// store's next save can't overwrite the approvals, aliases or install
    /// records it held. `setAside: false` leaves it, for files that are
    /// deleted after reading anyway.
    static func read<Value: Decodable>(_ type: Value.Type = Value.self, from file: URL?, decoder: JSONDecoder = JSONDecoder(), setAside: Bool = true) -> Value? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            if setAside { moveAside(file) }
            return nil
        }
    }

    /// Moves an undecodable file out of the way and says where it went.
    private static func moveAside(_ file: URL, now: Date = Date()) {
        let aside = file.appendingPathExtension("corrupt-\(Int(now.timeIntervalSince1970))")
        do {
            try? FileManager.default.removeItem(at: aside)
            try FileManager.default.moveItem(at: file, to: aside)
            HostLog.shared.write(.error, "\(file.lastPathComponent) was unreadable and was moved to \(aside.lastPathComponent); starting it empty")
        } catch {
            HostLog.shared.write(.error, "\(file.lastPathComponent) was unreadable and couldn't be moved aside: \(error.localizedDescription)")
        }
    }

    /// Writes the value in one step (the old file stays until the new one
    /// is whole), making the file's folder first.
    static func write(_ value: some Encodable, to file: URL, encoder: JSONEncoder = JSONEncoder()) throws {
        try write(encoder.encode(value), to: file)
    }

    /// Writes already-encoded JSON the same way.
    static func write(_ data: Data, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
}

extension JSONEncoder {
    /// For files a person may open: indented, keys in order, so two saves of
    /// the same state are the same bytes.
    static var readable: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// `readable`, with dates as ISO 8601.
    static var ledger: JSONEncoder {
        let encoder = readable
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    /// Reads what `JSONEncoder.ledger` wrote.
    static var ledger: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
