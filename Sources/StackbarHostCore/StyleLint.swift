import StackbarProtocol

/// Problems with a plugin's custom styling that `stackbarctl render` points
/// out: text that is hard to read on its background, and buttons that
/// VoiceOver and the agent can't name.
public enum StyleLint {
    /// WCAG AA for body text.
    public static let minimumContrast = 4.5

    public static func warnings(_ node: ViewNode) -> [String] {
        var found: [String] = []
        walk(node, foreground: nil, labeled: false, into: &found)
        var seen = Set<String>()
        return found.filter { seen.insert($0).inserted }
    }

    /// `labeled`: an enclosing node has an accessibility label, which names
    /// the buttons inside it.
    private static func walk(_ node: ViewNode, foreground: HexColor?, labeled: Bool, into found: inout [String]) {
        var foreground = foreground, labeled = labeled
        switch node {
        case .styled(let child, let style):
            if case .color(let color)? = style.foreground { foreground = color }
            if style.accessibilityLabel != nil { labeled = true }
            if case .color(let background)? = style.background?.paint, let text = foreground, !child.plainText.isEmpty {
                for dark in [false, true] {
                    let front = text.hex(dark: dark), back = background.hex(dark: dark)
                    if let ratio = HexColor.contrast(front, back), ratio < minimumContrast {
                        found.append("low contrast \(String(format: "%.1f", ratio)):1 for \(front) on \(back) in \(dark ? "dark" : "light") mode (\"\(child.plainText.prefix(30))\"); aim for \(minimumContrast):1")
                    }
                }
            }
        case .tappable(let content, let action) where !labeled && content.plainText.isEmpty:
            found.append("button {\(action)} has no text; give it .accessibilityLabel(...)")
        default:
            break
        }
        for child in node.children { walk(child, foreground: foreground, labeled: labeled, into: &found) }
    }
}
