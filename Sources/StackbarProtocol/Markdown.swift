import Foundation

/// What the host's editor draws for Markdown, worked out here as plain
/// ranges so Linux tests cover it; the Mac editor only applies the result.
///
/// Ranges are UTF-16 offsets, as NSString and NSTextView count. The
/// Markdown stays in the text: its markers are drawn faint, not hidden.
public enum MarkdownStyler {
    public enum Style: Equatable, Sendable {
        /// A `#` heading line, level 1 to 6.
        case heading(Int)
        case bold, italic, strikethrough
        /// `inline code`.
        case code
        /// A fenced block, fences included.
        case codeBlock
        /// A `>` line.
        case quote
        /// `-`, `*`, `+` or `1.` at the start of a list item.
        case listMarker
        /// `[ ]` or `[x]` in a task item: clicking it ticks the task.
        case taskBox(checked: Bool)
        /// The text of a ticked task.
        case done
        /// A link's text; `linkURL` is its `(url)`.
        case link
        case linkURL
        /// `---` on its own line.
        case rule
        /// Syntax: the `**`, `#`, `>` and backticks around what they style.
        case marker
    }

    public struct Span: Equatable, Sendable {
        public var location: Int
        public var length: Int
        public var style: Style

        public init(_ location: Int, _ length: Int, _ style: Style) {
            self.location = location
            self.length = length
            self.style = style
        }

        public var end: Int { location + length }
    }

    /// Spans in the order they should be applied: line styles first, then
    /// what is inside them, then markers.
    public static func spans(in text: String) -> [Span] {
        let string = text as NSString
        var spans: [Span] = []
        var inFence = false
        for line in lines(of: string) {
            let content = string.substring(with: NSRange(location: line.location, length: line.length))
            let start = line.location
            if content.hasPrefix("```") || content.hasPrefix("~~~") {
                spans.append(Span(start, line.length, .codeBlock))
                spans.append(Span(start, 3, .marker))
                inFence.toggle()
                continue
            }
            if inFence {
                spans.append(Span(start, line.length, .codeBlock))
                continue
            }
            if let match = first(Pattern.heading, in: content) {
                let hashes = match.range(at: 1)
                spans.append(Span(start, line.length, .heading(hashes.length)))
                spans.append(Span(start, match.range.length, .marker))
                spans += inline(content, offset: start, from: match.range.length)
                continue
            }
            if first(Pattern.rule, in: content) != nil {
                spans.append(Span(start, line.length, .rule))
                continue
            }
            if let match = first(Pattern.quote, in: content) {
                spans.append(Span(start, line.length, .quote))
                spans.append(Span(start, match.range.length, .marker))
                spans += inline(content, offset: start, from: match.range.length)
                continue
            }
            if let item = ListItem(content) {
                spans.append(Span(start + item.markerRange.location, item.markerRange.length, .listMarker))
                if let box = item.boxRange {
                    spans.append(Span(start + box.location, box.length, .taskBox(checked: item.checked)))
                    if item.checked, item.contentStart < line.length {
                        spans.append(Span(start + item.contentStart, line.length - item.contentStart, .done))
                    }
                }
                spans += inline(content, offset: start, from: item.contentStart)
                continue
            }
            spans += inline(content, offset: start, from: 0)
        }
        return spans
    }

    /// Emphasis, code and links inside one line, from `from` on.
    static func inline(_ line: String, offset: Int, from: Int) -> [Span] {
        let string = line as NSString
        guard from < string.length else { return [] }
        let scope = NSRange(location: from, length: string.length - from)
        var taken: [NSRange] = []
        var spans: [Span] = []
        func free(_ range: NSRange) -> Bool { !taken.contains { NSIntersectionRange($0, range).length > 0 } }
        func add(_ match: NSTextCheckingResult, _ style: Style, markerLength: Int) {
            let range = match.range
            guard free(range) else { return }
            taken.append(range)
            spans.append(Span(offset + range.location, range.length, style))
            spans.append(Span(offset + range.location, markerLength, .marker))
            spans.append(Span(offset + range.location + range.length - markerLength, markerLength, .marker))
        }
        // Code first: nothing inside backticks is emphasis.
        for match in Pattern.code.matches(in: line, range: scope) { add(match, .code, markerLength: 1) }
        for match in Pattern.link.matches(in: line, range: scope) where free(match.range) {
            taken.append(match.range)
            let text = match.range(at: 1)
            let url = match.range(at: 2)
            spans.append(Span(offset + text.location, text.length, .link))
            spans.append(Span(offset + match.range.location, 1, .marker))
            spans.append(Span(offset + text.location + text.length, 1, .marker))
            spans.append(Span(offset + url.location - 1, url.length + 2, .linkURL))
        }
        for match in Pattern.bold.matches(in: line, range: scope) { add(match, .bold, markerLength: 2) }
        for match in Pattern.strike.matches(in: line, range: scope) { add(match, .strikethrough, markerLength: 2) }
        for match in Pattern.italic.matches(in: line, range: scope) { add(match, .italic, markerLength: 1) }
        return spans
    }

    /// Each line's range without its line break. Text ending in a line
    /// break has an empty last line.
    public static func lines(of string: NSString) -> [NSRange] {
        var result: [NSRange] = []
        var start = 0
        for index in 0..<string.length where string.character(at: index) == 10 {
            result.append(trimmingReturn(NSRange(location: start, length: index - start), in: string))
            start = index + 1
        }
        result.append(trimmingReturn(NSRange(location: start, length: string.length - start), in: string))
        return result
    }

    private static func trimmingReturn(_ range: NSRange, in string: NSString) -> NSRange {
        guard range.length > 0, string.character(at: NSMaxRange(range) - 1) == 13 else { return range }
        return NSRange(location: range.location, length: range.length - 1)
    }

    static func first(_ pattern: NSRegularExpression, in line: String) -> NSTextCheckingResult? {
        pattern.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
    }

    enum Pattern {
        // Built once; the patterns are constants, so `try!` can't fail at run time.
        // swiftlint:disable force_try
        static let heading = try! NSRegularExpression(pattern: #"^(#{1,6})[ \t]+"#)
        static let rule = try! NSRegularExpression(pattern: #"^[ \t]*([-*_])([ \t]*\1){2,}[ \t]*$"#)
        static let quote = try! NSRegularExpression(pattern: #"^[ \t]*>[ \t]?"#)
        static let list = try! NSRegularExpression(pattern: #"^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+|$)(\[([ xX])\]([ \t]+|$))?"#)
        static let code = try! NSRegularExpression(pattern: #"`[^`\n]+`"#)
        static let bold = try! NSRegularExpression(pattern: #"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
        static let strike = try! NSRegularExpression(pattern: #"~~(?=\S)(.+?)(?<=\S)~~"#)
        static let italic = try! NSRegularExpression(pattern: #"(?<![*_\w])([*_])(?=\S)(.+?)(?<=\S)\1(?![*_\w])"#)
        static let link = try! NSRegularExpression(pattern: #"\[([^\]\n]+)\]\(([^)\s]+)\)"#)
        // swiftlint:enable force_try
    }
}

/// A list item's parts, in UTF-16 offsets within its line.
public struct ListItem: Equatable, Sendable {
    /// The whitespace before the marker.
    public var indent: String
    /// `-`, `*`, `+`, or a number with `.` or `)`.
    public var marker: String
    public var markerRange: NSRange
    /// The `[ ]` or `[x]`, when the item is a task.
    public var boxRange: NSRange?
    public var checked: Bool
    /// Where the item's own text starts.
    public var contentStart: Int

    public init?(_ line: String) {
        guard let match = MarkdownStyler.first(MarkdownStyler.Pattern.list, in: line) else { return nil }
        let string = line as NSString
        indent = string.substring(with: match.range(at: 1))
        markerRange = match.range(at: 2)
        marker = string.substring(with: markerRange)
        let box = match.range(at: 4)
        if box.location != NSNotFound {
            boxRange = NSRange(location: box.location, length: 3)
            checked = string.substring(with: match.range(at: 5)) != " "
        } else {
            boxRange = nil
            checked = false
        }
        contentStart = match.range.length
    }

    public var isTask: Bool { boxRange != nil }

    /// The marker the next item starts with: the same bullet, or the next number.
    public var nextMarker: String {
        guard let last = marker.last, last == "." || last == ")", let number = Int(marker.dropLast()) else { return marker }
        return "\(number + 1)\(last)"
    }
}

/// The editing keys a Markdown editor adds, as text changes the Mac editor
/// applies through its text view (so undo works). Offsets are UTF-16.
public enum MarkdownEditing {
    /// Replace `range` with `text`, then select `selection`.
    public struct Edit: Equatable, Sendable {
        public var range: NSRange
        public var text: String
        public var selection: NSRange

        public init(range: NSRange, text: String, selection: NSRange) {
            self.range = range
            self.text = text
            self.selection = selection
        }
    }

    /// The line around `location`, without its line break.
    static func line(in string: NSString, at location: Int) -> NSRange {
        let lines = MarkdownStyler.lines(of: string)
        return lines.last { $0.location <= location } ?? NSRange(location: 0, length: 0)
    }

    /// Return on a list item: the next item, or, on an empty one, the end of
    /// the list. `nil` when Return should just break the line.
    public static func newline(in text: String, selection: NSRange) -> Edit? {
        let string = text as NSString
        guard selection.length == 0 else { return nil }
        let lineRange = line(in: string, at: selection.location)
        let line = string.substring(with: lineRange)
        guard let item = ListItem(line), selection.location >= lineRange.location + item.contentStart else { return nil }
        let rest = (line as NSString).substring(from: item.contentStart)
        if rest.trimmingCharacters(in: .whitespaces).isEmpty {
            // An empty item ends the list: its marker goes, the line stays.
            return Edit(range: lineRange, text: "", selection: NSRange(location: lineRange.location, length: 0))
        }
        let next = "\n" + item.indent + item.nextMarker + " " + (item.isTask ? "[ ] " : "")
        let location = selection.location + (next as NSString).length
        return Edit(range: selection, text: next, selection: NSRange(location: location, length: 0))
    }

    /// ⌘Return or a click on a box: ticks or unticks the task on the line at
    /// `location`, makes a list item a task, or a plain line a task item.
    public static func toggleTask(in text: String, at location: Int, selection: NSRange? = nil) -> Edit? {
        let string = text as NSString
        let lineRange = line(in: string, at: location)
        let line = string.substring(with: lineRange)
        let keep = selection ?? NSRange(location: location, length: 0)
        if let item = ListItem(line) {
            if let box = item.boxRange {
                let range = NSRange(location: lineRange.location + box.location + 1, length: 1)
                return Edit(range: range, text: item.checked ? " " : "x", selection: keep)
            }
            let insert = NSRange(location: lineRange.location + item.contentStart, length: 0)
            return Edit(range: insert, text: "[ ] ", selection: shifted(keep, after: insert.location, by: 4))
        }
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let insert = NSRange(location: lineRange.location + (String(indent) as NSString).length, length: 0)
        return Edit(range: insert, text: "- [ ] ", selection: shifted(keep, after: insert.location, by: 6))
    }

    /// Tab or ⇧Tab on list lines: one level in or out for every selected
    /// line. `nil` when no selected line is a list item (Tab types a tab).
    public static func indent(in text: String, selection: NSRange, outdent: Bool) -> Edit? {
        let string = text as NSString
        let lines = MarkdownStyler.lines(of: string).filter {
            NSMaxRange($0) >= selection.location && $0.location <= NSMaxRange(selection)
        }
        guard let first = lines.first, let last = lines.last,
              lines.contains(where: { ListItem(string.substring(with: $0)) != nil }) else { return nil }
        let whole = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        var changed: [String] = []
        var delta = 0
        var firstDelta = 0
        for (index, range) in lines.enumerated() {
            var line = string.substring(with: range)
            var change = 0
            if ListItem(line) != nil {
                if outdent {
                    if line.hasPrefix("\t") { line.removeFirst(); change = -1 } else {
                        let spaces = min(4, line.prefix { $0 == " " }.count)
                        line.removeFirst(spaces)
                        change = -spaces
                    }
                } else {
                    line = "\t" + line
                    change = 1
                }
            }
            if index == 0 { firstDelta = change }
            delta += change
            changed.append(line)
        }
        guard delta != 0 || firstDelta != 0 else { return nil }
        let replacement = changed.joined(separator: "\n")
        let start = max(first.location, selection.location + firstDelta)
        let length = max(0, selection.length + delta - firstDelta)
        return Edit(range: whole, text: replacement, selection: NSRange(location: start, length: length))
    }

    /// ⌘B, ⌘I, ⇧⌘X, ⌘E: wraps the selection in `marker`, or unwraps it when
    /// it already is. With nothing selected it types the pair and puts the
    /// cursor between.
    public static func wrap(in text: String, selection: NSRange, marker: String) -> Edit {
        let string = text as NSString
        let size = (marker as NSString).length
        let before = NSRange(location: selection.location - size, length: size)
        let after = NSRange(location: NSMaxRange(selection), length: size)
        if before.location >= 0, NSMaxRange(after) <= string.length,
           string.substring(with: before) == marker, string.substring(with: after) == marker {
            let whole = NSRange(location: before.location, length: selection.length + 2 * size)
            return Edit(range: whole, text: string.substring(with: selection), selection: NSRange(location: before.location, length: selection.length))
        }
        let selected = string.substring(with: selection)
        if selected.count >= 2 * marker.count, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let inner = String(selected.dropFirst(marker.count).dropLast(marker.count))
            return Edit(range: selection, text: inner, selection: NSRange(location: selection.location, length: (inner as NSString).length))
        }
        return Edit(range: selection, text: marker + selected + marker, selection: NSRange(location: selection.location + size, length: selection.length))
    }

    /// ⌘K: the selection as a link's text, with the cursor where the URL goes.
    public static func link(in text: String, selection: NSRange) -> Edit {
        let selected = (text as NSString).substring(with: selection)
        let replacement = "[\(selected)]()"
        let cursor = selected.isEmpty ? selection.location + 1 : selection.location + (replacement as NSString).length - 1
        return Edit(range: selection, text: replacement, selection: NSRange(location: cursor, length: 0))
    }

    static func shifted(_ range: NSRange, after location: Int, by amount: Int) -> NSRange {
        range.location >= location ? NSRange(location: range.location + amount, length: range.length) : range
    }
}

/// Who wins when the plugin's text and the user's typing meet: the rules
/// an editor node follows, kept here so Linux tests cover them.
public struct EditorSync: Equatable, Sendable {
    /// The document on screen.
    public private(set) var document: String
    /// The text the plugin is known to have: what it rendered or was sent.
    public private(set) var saved: String
    /// The user typed since the last send.
    public private(set) var isDirty = false
    /// Texts the plugin had before `saved`: a render made before the
    /// plugin heard the latest send can carry one of them, and showing it
    /// would undo the user's words.
    private var earlier: [String] = []

    public init(document: String, text: String) {
        self.document = document
        saved = text
    }

    /// A render arrived. Returns the text to show in place of the user's,
    /// or nil to keep what is on screen.
    public mutating func render(document: String, text: String) -> String? {
        if document != self.document {
            self.document = document
            saved = text
            earlier = []
            isDirty = false
            return text
        }
        guard text != saved, !isDirty, !earlier.contains(text) else { return nil }
        keep(text)
        return text
    }

    /// The user typed.
    public mutating func edited() {
        isDirty = true
    }

    /// Time to send (a pause, focus lost, closing). Returns the text to send,
    /// or nil when the plugin already has it.
    public mutating func flush(_ current: String) -> String? {
        isDirty = false
        guard current != saved else { return nil }
        keep(current)
        return current
    }

    private mutating func keep(_ text: String) {
        earlier.append(saved)
        if earlier.count > 8 { earlier.removeFirst() }
        saved = text
    }
}
