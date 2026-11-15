#if canImport(AppKit)
import AppKit

/// Whether an input method is composing in the focused text field: Japanese,
/// Chinese or Korean text that is typed but not yet confirmed (underlined).
///
/// SwiftUI's `onKeyPress` sees a key before the field's input method does, so
/// a handler that takes ↑, ↓, Tab or Return would move the selection or run
/// a row while the user is picking a candidate. Handlers return `.ignored`
/// while this is true, and the input method gets the key.
@MainActor
public enum TextComposition {
    public static var isComposing: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder as? NSTextInputClient else { return false }
        return responder.hasMarkedText()
    }
}
#endif
