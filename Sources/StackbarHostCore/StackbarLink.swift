import Foundation

/// Any link the app is asked to open, read once: one of Stackbar's own
/// (`stackbar://…`) or one that belongs to another app. Every way a link
/// arrives (macOS handing one over, the palette, a plugin's `open`, a
/// notification or alert button) goes through one dispatcher in the app, so
/// a Stackbar link is handled by this copy of Stackbar and never sent back
/// out through Launch Services, where another copy (a dev build) could take
/// it.
public enum StackbarLink: Equatable, Sendable {
    /// `stackbar://settings[/page]`, `stackbar://store`.
    case place(AppLink)
    /// `stackbar://store/<plugin-id>`.
    case storePage(StoreLink)
    /// `stackbar://commands/<plugin-id>/<command-id>?name=value`.
    case command(CommandLink)
    /// A `stackbar://` link that names nothing Stackbar knows.
    case unknown(URL)
    /// Any other scheme: another app opens it.
    case external(URL)

    public init(_ url: URL) {
        guard url.scheme?.lowercased() == CommandLink.scheme else {
            self = .external(url)
            return
        }
        if let link = StoreLink(url) {
            self = .storePage(link)
        } else if let link = AppLink(url) {
            self = .place(link)
        } else if let link = CommandLink(url.absoluteString) {
            self = .command(link)
        } else {
            self = .unknown(url)
        }
    }

    public init?(_ text: String) {
        guard let url = URL(string: text), url.scheme != nil else { return nil }
        self.init(url)
    }

    /// One of Stackbar's own pages, which only shows something: a plugin
    /// may open these without declaring the scheme. A command link still
    /// needs it, since it can run something.
    public var isPage: Bool {
        switch self {
        case .place, .storePage: return true
        case .command, .unknown, .external: return false
        }
    }
}
