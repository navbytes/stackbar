#if canImport(SwiftUI) && canImport(AppKit)
import AppKit
import SwiftUI
import StackbarProtocol

/// An `editor` node: an NSTextView the host owns while the user types.
///
/// The text goes to the plugin 0.6 s after the last keystroke, and at once
/// when the editor loses focus, its window stops being key (a popover or
/// window closing) or it leaves the screen. `EditorSync` decides when a
/// render may replace what is on screen. With `markdown`, the text is
/// styled from `MarkdownStyler` after each change and the keys of
/// `MarkdownEditing` apply through the text view, so undo covers them.
struct EditorNodeView: NSViewRepresentable {
    let editor: EditorNode
    let send: SendAction

    func makeCoordinator() -> Coordinator {
        Coordinator(editor: editor, send: send)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 320, height: EditorNode.defaultHeight))
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.font = Coordinator.baseFont
        textView.typingAttributes = Coordinator.baseAttributes
        textView.placeholder = editor.placeholder
        textView.wantsFocus = editor.focus == true
        textView.delegate = context.coordinator
        textView.coordinator = context.coordinator
        textView.string = editor.text
        textView.setAccessibilityLabel(editor.placeholder ?? "Text")

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        context.coordinator.textView = textView
        context.coordinator.restyle()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(editor: editor, send: send)
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.flush()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        static let baseFont = NSFont.systemFont(ofSize: NSFont.systemFontSize + 1)
        static let baseAttributes: [NSAttributedString.Key: Any] = [.font: baseFont, .foregroundColor: NSColor.textColor]

        private var editor: EditorNode
        private var send: SendAction
        private var sync: EditorSync
        private var pending: Task<Void, Never>?
        weak var textView: EditorTextView?
        /// Where the task boxes are, for clicks.
        private(set) var boxes: [NSRange] = []

        init(editor: EditorNode, send: @escaping SendAction) {
            self.editor = editor
            self.send = send
            sync = EditorSync(document: editor.document, text: editor.text)
        }

        var isMarkdown: Bool { editor.markdown == true }

        func update(editor: EditorNode, send: @escaping SendAction) {
            let documentChanged = editor.document != self.editor.document
            self.editor = editor
            self.send = send
            guard let textView else { return }
            textView.placeholder = editor.placeholder
            textView.wantsFocus = editor.focus == true
            if documentChanged {
                // What the user typed in the last document goes to the plugin first.
                pending?.cancel()
                pending = nil
            }
            guard let replacement = sync.render(document: editor.document, text: editor.text) else { return }
            let selection = textView.selectedRange()
            textView.string = replacement
            if documentChanged {
                // Undo stays within one document.
                textView.undoManager?.removeAllActions()
                let end = (replacement as NSString).length
                textView.setSelectedRange(NSRange(location: end, length: 0))
                if editor.focus == true { textView.window?.makeFirstResponder(textView) }
            } else {
                let length = (replacement as NSString).length
                textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            }
            restyle()
            textView.needsDisplay = true
        }

        // MARK: Sending

        func textDidChange(_ notification: Notification) {
            sync.edited()
            restyle()
            textView?.needsDisplay = true
            pending?.cancel()
            pending = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                self?.flush()
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            flush()
        }

        /// Sends what is on screen when the plugin doesn't have it yet.
        func flush() {
            pending?.cancel()
            pending = nil
            guard let textView, let text = sync.flush(textView.string) else { return }
            send(editor.action, .text(text))
        }

        // MARK: Markdown

        func restyle() {
            guard let textView, let storage = textView.textStorage else { return }
            let whole = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes(Self.baseAttributes, range: whole)
            var boxes: [NSRange] = []
            if isMarkdown {
                for span in MarkdownStyler.spans(in: textView.string) {
                    let range = NSRange(location: span.location, length: span.length)
                    guard range.length > 0, NSMaxRange(range) <= storage.length else { continue }
                    if case .taskBox = span.style { boxes.append(range) }
                    apply(span.style, to: range, in: storage)
                }
            }
            storage.endEditing()
            self.boxes = boxes
            textView.typingAttributes = Self.baseAttributes
        }

        private func apply(_ style: MarkdownStyler.Style, to range: NSRange, in storage: NSTextStorage) {
            let size = Self.baseFont.pointSize
            switch style {
            case .heading(let level):
                let scale: [CGFloat] = [1.6, 1.35, 1.2, 1.1, 1.05, 1]
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size * scale[min(max(level, 1), 6) - 1], weight: .bold), range: range)
            case .bold:
                convert(range, in: storage, trait: .boldFontMask)
            case .italic:
                convert(range, in: storage, trait: .italicFontMask)
            case .strikethrough:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case .code, .codeBlock:
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size * 0.95, weight: .regular), range: range)
                storage.addAttribute(.backgroundColor, value: NSColor.textColor.withAlphaComponent(0.07), range: range)
            case .quote:
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            case .listMarker:
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            case .taskBox:
                storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: range)
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size, weight: .semibold), range: range)
                storage.addAttribute(.cursor, value: NSCursor.pointingHand, range: range)
            case .done:
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case .link:
                storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case .linkURL, .rule, .marker:
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
            }
        }

        private func convert(_ range: NSRange, in storage: NSTextStorage, trait: NSFontTraitMask) {
            storage.enumerateAttribute(.font, in: range) { value, part, _ in
                let font = value as? NSFont ?? Self.baseFont
                storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: part)
            }
        }

        // MARK: Keys

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard isMarkdown else { return false }
            let text = textView.string
            let selection = textView.selectedRange()
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                return apply(MarkdownEditing.newline(in: text, selection: selection))
            case #selector(NSResponder.insertTab(_:)):
                return apply(MarkdownEditing.indent(in: text, selection: selection, outdent: false))
            case #selector(NSResponder.insertBacktab(_:)):
                return apply(MarkdownEditing.indent(in: text, selection: selection, outdent: true))
            default:
                return false
            }
        }

        /// ⌘B, ⌘I, ⇧⌘X, ⌘E, ⌘K and ⌘Return. True when the key was used.
        func keyEquivalent(_ event: NSEvent) -> Bool {
            guard isMarkdown, let textView, let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let text = textView.string
            let selection = textView.selectedRange()
            if modifiers == [.command, .shift] {
                return key == "x" && apply(MarkdownEditing.wrap(in: text, selection: selection, marker: "~~"))
            }
            guard modifiers == [.command] else { return false }
            switch key {
            case "b": return apply(MarkdownEditing.wrap(in: text, selection: selection, marker: "**"))
            case "i": return apply(MarkdownEditing.wrap(in: text, selection: selection, marker: "*"))
            case "e": return apply(MarkdownEditing.wrap(in: text, selection: selection, marker: "`"))
            case "k": return apply(MarkdownEditing.link(in: text, selection: selection))
            case "\r": return apply(MarkdownEditing.toggleTask(in: text, at: selection.location, selection: selection))
            default: return false
            }
        }

        /// A click on a task box ticks it. True when the click was on one.
        func click(at index: Int) -> Bool {
            guard isMarkdown, let textView, let box = boxes.first(where: { $0.location <= index && index <= NSMaxRange($0) }) else { return false }
            return apply(MarkdownEditing.toggleTask(in: textView.string, at: box.location, selection: textView.selectedRange()))
        }

        /// Makes an edit through the text view, so it can be undone and is sent.
        @discardableResult
        private func apply(_ edit: MarkdownEditing.Edit?) -> Bool {
            guard let edit, let textView, let storage = textView.textStorage else { return false }
            guard textView.shouldChangeText(in: edit.range, replacementString: edit.text) else { return true }
            storage.replaceCharacters(in: edit.range, with: edit.text)
            textView.didChangeText()
            let length = storage.length
            let location = min(edit.selection.location, length)
            textView.setSelectedRange(NSRange(location: location, length: min(edit.selection.length, length - location)))
            textView.scrollRangeToVisible(textView.selectedRange())
            return true
        }
    }
}

/// The text view behind an editor node: a placeholder, Markdown keys and
/// clickable task boxes, and a send whenever its window stops being key.
final class EditorTextView: NSTextView {
    weak var coordinator: EditorNodeView.Coordinator?
    var placeholder: String? {
        didSet { if placeholder != oldValue { needsDisplay = true } }
    }
    var wantsFocus = false
    private var observers: [NSObjectProtocol] = []

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, coordinator?.keyEquivalent(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 1, event.modifierFlags.intersection([.shift, .command, .option]).isEmpty,
           coordinator?.click(at: characterIndexForInsertion(at: point)) == true {
            return
        }
        super.mouseDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { return }
        // Closing a window or popover, or switching away, sends the text.
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.coordinator?.flush() }
            })
        }
        if wantsFocus {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let placeholder, !placeholder.isEmpty else { return }
        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0), y: textContainerInset.height)
        (placeholder as NSString).draw(at: origin, withAttributes: [
            .font: font ?? EditorNodeView.Coordinator.baseFont,
            .foregroundColor: NSColor.placeholderTextColor,
        ])
    }
}
#endif
