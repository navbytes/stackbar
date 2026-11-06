#if os(macOS)
import AppKit
import StackbarHostCore
import StackbarProtocol
import Vision

/// Protocol 21: opening a terminal, reading text in images and on screen.
/// Plugins run sandboxed and can't load Vision or start a terminal, so the
/// host does it for them.
extension MacSystem {
    // MARK: Terminal

    /// Writes a `.command` file that runs the words, each single-quoted, and
    /// hands it to whatever opens `.command` files. The file goes once the
    /// terminal has had time to read it.
    func openInTerminal(_ command: [String], title: String?) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StackbarTerminal", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(UUID().uuidString).command")
        var script = "#!/bin/zsh -l\n"
        if let title, !title.isEmpty {
            let clean = title.filter { !$0.isNewline && $0.asciiValue.map { $0 >= 32 } ?? true }
            script += "printf '\\033]0;%s\\007' \(Self.quoted(clean))\n"
        }
        script += "rm -f \(Self.quoted(file.path))\n"
        script += command.map(Self.quoted).joined(separator: " ") + "\n"
        try Data(script.utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        let opened = await MainActor.run { NSWorkspace.shared.open(file) }
        guard opened else {
            try? FileManager.default.removeItem(at: file)
            throw SystemServiceError("no app opens .command files; set Terminal as their default app in Finder > Get Info")
        }
        Task.detached {
            try? await Task.sleep(for: .seconds(60))
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// One shell word: `'…'`, with a `'` inside written as `'\''`.
    static func quoted(_ word: String) -> String {
        "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: Text in images

    func recognizeText(imageID: String, languages: [String]?) async throws -> StackbarProtocol.RecognizedText {
        guard let data = images.data(for: imageID) else { throw SystemServiceError("no kept clipboard image \(imageID)") }
        guard let image = NSBitmapImageRep(data: data)?.cgImage else { throw SystemServiceError("clipboard item \(imageID) is not an image") }
        return try await Self.read(image, languages: languages)
    }

    /// Runs `screencapture -i` (the ⇧⌘4 crosshair) into a temporary file and
    /// reads it. Esc leaves no file, which is nil.
    func captureScreenText(languages: [String]?) async throws -> StackbarProtocol.RecognizedText? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("stackbar-capture-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        let status = try await Self.capture(to: file)
        guard FileManager.default.fileExists(atPath: file.path) else {
            if status == 0 { return nil }
            throw SystemServiceError("the screen couldn't be captured; allow Stackbar in System Settings > Privacy & Security > Screen & System Audio Recording")
        }
        guard let image = NSImage(contentsOf: file)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw SystemServiceError("the screen capture couldn't be read")
        }
        return try await Self.read(image, languages: languages)
    }

    private static func capture(to file: URL) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-x", "-o", file.path]
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: SystemServiceError("screencapture couldn't start: \(error.localizedDescription)"))
            }
        }
    }

    /// Top to bottom (Vision's origin is the bottom left), then left to right.
    private static func readingOrder(_ first: VNRecognizedTextObservation, _ second: VNRecognizedTextObservation) -> Bool {
        let a: CGRect = first.boundingBox
        let b: CGRect = second.boundingBox
        if abs(a.midY - b.midY) > 0.01 { return a.midY > b.midY }
        return a.minX < b.minX
    }

    private static func read(_ image: CGImage, languages: [String]?) async throws -> StackbarProtocol.RecognizedText {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if let languages, !languages.isEmpty {
                request.recognitionLanguages = languages
            } else {
                request.automaticallyDetectsLanguage = true
            }
            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            } catch {
                throw SystemServiceError("text recognition failed: \(error.localizedDescription)")
            }
            let observations = (request.results ?? []).sorted(by: Self.readingOrder)
            let lines = observations.compactMap { observation -> StackbarProtocol.RecognizedText.Line? in
                guard let best = observation.topCandidates(1).first else { return nil }
                return StackbarProtocol.RecognizedText.Line(text: best.string, confidence: Double(best.confidence))
            }
            return StackbarProtocol.RecognizedText(lines: Array(lines.prefix(2000)))
        }.value
    }
}
#endif
