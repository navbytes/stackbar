import Foundation

/// Text with placeholders, in Raycast's syntax, for quicklinks and snippets.
///
/// ```swift
/// let template = try Template("https://github.com/{argument name=\"org\" default=\"navbytes\"}/{argument name=\"repo\"}/issues?q={argument name=\"q\"}")
/// template.arguments    // org (optional), repo, q: the command's arguments
/// let url = try template.render(["repo": "stackbar", "q": "is:open"], encoding: .url).text
/// ```
///
/// Placeholders are `{name key="value" | modifier | modifier}`:
///
/// - `{argument name="q" default="x" options="a, b"}`: at most 3 names; a
///   repeated name shares one value. `{argument}` alone is named "argument".
/// - `{clipboard}` and `{selection}`: what the environment supplies (the
///   plugin reads them with `.clipboard` and `.context`).
/// - `{date}`, `{time}`, `{datetime}`, `{day}`, with `format="yyyy-MM-dd"`,
///   `offset="+2d -3h"` (y, M, w, d, h, m) and `locale="fr-FR"`.
/// - `{uuid}`, `{cursor}` (where the caret goes after a paste) and
///   `{snippet name="sig"}` (another snippet, one level deep).
///
/// Modifiers: `uppercase`, `lowercase`, `trim`, `percent-encode`,
/// `json-stringify` and `raw`, applied left to right. With `encoding: .url`
/// argument, clipboard and selection values are percent-encoded unless
/// `raw` (or `percent-encode`) is given; the template's own text never is.
/// `\{` is a literal brace, and anything in braces that isn't a placeholder
/// stays exactly as written.
public struct Template: Equatable, Sendable {
    public struct Placeholder: Equatable, Sendable {
        public var name: String
        public var options: [String: String]
        public var modifiers: [String]
        /// As written, braces included.
        public var source: String
    }

    public enum Piece: Equatable, Sendable {
        case text(String)
        case placeholder(Placeholder)
    }

    public enum Encoding: Sendable {
        case none
        /// For a link: values are percent-encoded.
        case url
    }

    /// What the placeholders read, injected so rendering is deterministic.
    public struct Environment: Sendable {
        public var clipboard: String?
        public var selection: String?
        public var now: Date
        public var timeZone: TimeZone
        public var locale: Locale
        public var uuid: @Sendable () -> String
        /// Other snippets' text by name, for `{snippet name=}`.
        public var snippets: [String: String]

        public init(clipboard: String? = nil, selection: String? = nil, now: Date = Date(), timeZone: TimeZone = .current, locale: Locale = .current, uuid: @escaping @Sendable () -> String = { UUID().uuidString }, snippets: [String: String] = [:]) {
            self.clipboard = clipboard
            self.selection = selection
            self.now = now
            self.timeZone = timeZone
            self.locale = locale
            self.uuid = uuid
            self.snippets = snippets
        }
    }

    public struct Rendered: Equatable, Sendable {
        public var text: String
        /// Characters after `{cursor}`, for `CommandResult.paste(_:cursorFromEnd:)`.
        public var cursorFromEnd: Int?
    }

    public struct Failure: Error, CustomStringConvertible, Equatable, Sendable {
        /// The placeholder as written, or empty for the template as a whole.
        public var placeholder: String
        public var message: String
        public var description: String { placeholder.isEmpty ? message : "\(placeholder): \(message)" }
    }

    public static let names: Set<String> = ["argument", "clipboard", "selection", "date", "time", "datetime", "day", "uuid", "cursor", "snippet"]
    public static let modifiers: Set<String> = ["uppercase", "lowercase", "trim", "percent-encode", "json-stringify", "raw"]
    public static let maxArguments = 3

    public let source: String
    public let pieces: [Piece]
    /// Brace groups kept as text that look like a mistyped placeholder:
    /// `{clipbaord}`, `{date | upper}`. For a form to warn about.
    public let unrecognized: [String]

    /// Parses `source`. Throws only for what can't be rendered at all: more
    /// than three arguments, or one with conflicting defaults.
    public init(_ source: String) throws {
        self.source = source
        (pieces, unrecognized) = Self.parse(source)
        _ = try Self.arguments(of: pieces)
    }

    /// The command arguments the template asks for, in order of first use.
    public var arguments: [ArgumentSpec] {
        (try? Self.arguments(of: pieces)) ?? []
    }

    public var placeholders: [Placeholder] {
        pieces.compactMap { if case .placeholder(let placeholder) = $0 { return placeholder } else { return nil } }
    }

    public func uses(_ name: String) -> Bool { placeholders.contains { $0.name == name } }

    public func render(_ values: [String: String] = [:], in environment: Environment = Environment(), encoding: Encoding = .none) throws -> Rendered {
        try render(values, environment, encoding, nested: false)
    }

    private func render(_ values: [String: String], _ environment: Environment, _ encoding: Encoding, nested: Bool) throws -> Rendered {
        let specs = try Self.arguments(of: pieces)
        var output = ""
        var cursorText: String?
        for piece in pieces {
            switch piece {
            case .text(let text):
                output += text
            case .placeholder(let placeholder):
                func fail(_ message: String) -> Failure { Failure(placeholder: placeholder.source, message: message) }
                var value: String
                var isInput = false
                switch placeholder.name {
                case "argument":
                    let name = placeholder.options["name"] ?? "argument"
                    let spec = specs.first { $0.name == name }
                    let given = values[name].flatMap { $0.isEmpty ? nil : $0 }
                    guard let resolved = given ?? spec?.defaultValue else { throw fail("needs a value for \(name)") }
                    if let options = spec?.options, !options.contains(resolved) {
                        throw fail("\(resolved) is not one of " + options.joined(separator: ", "))
                    }
                    value = resolved
                    isInput = true
                case "clipboard":
                    if let offset = placeholder.options["offset"], offset != "0" {
                        throw fail("older clipboard entries need Clipboard History sharing, which isn't available yet")
                    }
                    value = environment.clipboard ?? ""
                    isInput = true
                case "selection":
                    value = environment.selection ?? ""
                    isInput = true
                case "date", "time", "datetime", "day":
                    value = try Self.date(placeholder, environment, fail)
                case "uuid":
                    value = environment.uuid()
                case "cursor":
                    if cursorText == nil { cursorText = output }
                    continue
                case "snippet":
                    guard !nested else { throw fail("a snippet inside a snippet can't include another") }
                    guard let name = placeholder.options["name"], let text = environment.snippets[name] else {
                        throw fail("no snippet named \(placeholder.options["name"] ?? "(none)")")
                    }
                    let inner = try Template(text).render(values, environment, encoding, nested: true)
                    value = inner.text
                default:
                    value = placeholder.source
                }
                var encoded = false
                for modifier in placeholder.modifiers {
                    switch modifier {
                    case "uppercase": value = value.uppercased()
                    case "lowercase": value = value.lowercased()
                    case "trim": value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    case "percent-encode":
                        value = Self.percentEncode(value)
                        encoded = true
                    case "json-stringify":
                        value = Self.jsonString(value)
                    case "raw": encoded = true
                    default: break
                    }
                }
                if encoding == .url, isInput, !encoded { value = Self.percentEncode(value) }
                output += value
            }
        }
        let fromEnd = cursorText.map { output.count - $0.count }
        return Rendered(text: output, cursorFromEnd: fromEnd)
    }

    // MARK: Parsing

    static func parse(_ source: String) -> ([Piece], [String]) {
        var pieces: [Piece] = []
        var rejected: [String] = []
        var text = ""
        let characters = Array(source)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\\", index + 1 < characters.count, characters[index + 1] == "{" || characters[index + 1] == "}" {
                text.append(characters[index + 1])
                index += 2
                continue
            }
            if character == "{", let end = closingBrace(characters, from: index) {
                let group = String(characters[index...end])
                if let placeholder = placeholder(group) {
                    if !text.isEmpty { pieces.append(.text(text)) }
                    text = ""
                    pieces.append(.placeholder(placeholder))
                } else {
                    text += group
                    let inner = group.dropFirst().dropLast()
                    if let first = inner.first, first.isLetter, !inner.contains(" ") || inner.contains("=") || inner.contains("|") {
                        rejected.append(group)
                    }
                }
                index = end + 1
                continue
            }
            text.append(character)
            index += 1
        }
        if !text.isEmpty { pieces.append(.text(text)) }
        return (pieces, rejected)
    }

    /// The `}` closing the brace at `start`, outside quotes; nil when there
    /// is none before the next `{` or the end of the line.
    private static func closingBrace(_ characters: [Character], from start: Int) -> Int? {
        var quoted = false
        var index = start + 1
        while index < characters.count {
            let character = characters[index]
            if quoted {
                if character == "\\" { index += 2; continue }
                if character == "\"" { quoted = false }
            } else {
                if character == "\"" { quoted = true }
                if character == "}" { return index }
                if character == "{" || character == "\n" { return nil }
            }
            index += 1
        }
        return nil
    }

    /// `{name key="value" key=value | modifier}`, or nil when it isn't one.
    static func placeholder(_ group: String) -> Placeholder? {
        let inner = Array(group.dropFirst().dropLast())
        var index = 0
        func skipSpaces() { while index < inner.count, inner[index] == " " || inner[index] == "\t" { index += 1 } }
        func word() -> String {
            var result = ""
            while index < inner.count, inner[index].isLetter || inner[index].isNumber || inner[index] == "-" || inner[index] == "_" {
                result.append(inner[index])
                index += 1
            }
            return result
        }
        skipSpaces()
        let name = word()
        guard names.contains(name) else { return nil }
        var options: [String: String] = [:]
        var modifiers: [String] = []
        while true {
            skipSpaces()
            guard index < inner.count else { break }
            if inner[index] == "|" {
                index += 1
                skipSpaces()
                let modifier = word()
                guard Self.modifiers.contains(modifier) else { return nil }
                modifiers.append(modifier)
                continue
            }
            guard modifiers.isEmpty else { return nil }
            let key = word()
            guard !key.isEmpty, index < inner.count, inner[index] == "=" else { return nil }
            index += 1
            var value = ""
            if index < inner.count, inner[index] == "\"" {
                index += 1
                var closed = false
                while index < inner.count {
                    if inner[index] == "\\", index + 1 < inner.count {
                        value.append(inner[index + 1])
                        index += 2
                        continue
                    }
                    if inner[index] == "\"" {
                        closed = true
                        index += 1
                        break
                    }
                    value.append(inner[index])
                    index += 1
                }
                guard closed else { return nil }
            } else {
                while index < inner.count, inner[index] != " ", inner[index] != "|" {
                    value.append(inner[index])
                    index += 1
                }
            }
            options[key] = value
        }
        return Placeholder(name: name, options: options, modifiers: modifiers, source: group)
    }

    static func arguments(of pieces: [Piece]) throws -> [ArgumentSpec] {
        var specs: [ArgumentSpec] = []
        for case .placeholder(let placeholder) in pieces where placeholder.name == "argument" {
            let name = placeholder.options["name"] ?? "argument"
            let defaultValue = placeholder.options["default"]
            let options = placeholder.options["options"].map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            if let index = specs.firstIndex(where: { $0.name == name }) {
                if let defaultValue {
                    if let existing = specs[index].defaultValue, existing != defaultValue {
                        throw Failure(placeholder: placeholder.source, message: "\(name) already has the default \"\(existing)\"")
                    }
                    specs[index].defaultValue = defaultValue
                    specs[index].required = false
                }
                if let options, specs[index].options == nil { specs[index].options = options }
                continue
            }
            specs.append(ArgumentSpec(name, placeholder: name, required: defaultValue == nil, defaultValue: defaultValue, options: options))
        }
        if specs.count > maxArguments {
            throw Failure(placeholder: "", message: "at most \(maxArguments) arguments; this asks for " + specs.map(\.name).joined(separator: ", "))
        }
        return specs
    }

    // MARK: Values

    static func date(_ placeholder: Placeholder, _ environment: Environment, _ fail: (String) -> Failure) throws -> String {
        var date = environment.now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = environment.timeZone
        if let offset = placeholder.options["offset"] {
            for token in offset.split(separator: " ") {
                guard let shifted = shift(date, by: String(token), calendar: calendar) else {
                    throw fail("offset \"\(offset)\" should look like +2d -3h (y, M, w, d, h, m)")
                }
                date = shifted
            }
        }
        let formatter = DateFormatter()
        formatter.timeZone = environment.timeZone
        formatter.locale = placeholder.options["locale"].map { Locale(identifier: $0) } ?? environment.locale
        formatter.calendar = calendar
        if let format = placeholder.options["format"] {
            guard !format.isEmpty else { throw fail("format is empty") }
            formatter.dateFormat = format
        } else {
            switch placeholder.name {
            case "date": formatter.dateStyle = .medium
            case "time": formatter.timeStyle = .short
            case "day": formatter.dateFormat = "EEEE"
            default:
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
            }
        }
        return formatter.string(from: date)
    }

    /// `+2d`, `-3h`, `1M`.
    static func shift(_ date: Date, by token: String, calendar: Calendar) -> Date? {
        var text = Substring(token)
        var sign = 1
        if text.first == "+" { text = text.dropFirst() } else if text.first == "-" { sign = -1; text = text.dropFirst() }
        guard let unit = text.last, let amount = Int(text.dropLast()) else { return nil }
        let component: Calendar.Component
        switch unit {
        case "y": component = .year
        case "M": component = .month
        case "w": component = .weekOfYear
        case "d": component = .day
        case "h": component = .hour
        case "m": component = .minute
        default: return nil
        }
        return calendar.date(byAdding: component, value: sign * amount, to: date)
    }

    /// Like JavaScript's `encodeURIComponent`.
    static func percentEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(127)))
        allowed.insert(charactersIn: "-_.!~*'()")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    static func jsonString(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return (try? encoder.encode(text)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
    }
}
