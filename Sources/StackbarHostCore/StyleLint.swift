import StackbarProtocol

/// Problems with a plugin's custom styling that `stackbarctl render` points
/// out: text that is hard to read on its background, and buttons that
/// VoiceOver and the agent can't name.
public enum StyleLint {
    /// WCAG AA for body text.
    public static let minimumContrast = 4.5

    public static func warnings(_ node: ViewNode) -> [String] {
        var found: [String] = []
        walk(node, foreground: nil, backdrop: nil, labeled: false, into: &found)
        var seen = Set<String>()
        return found.filter { seen.insert($0).inserted }
    }

    /// `labeled`: an enclosing node has an accessibility label, which names
    /// the buttons inside it. `backdrop`: the nearest enclosing background,
    /// which a see-through one is seen against (the panel when `nil`).
    private static func walk(_ node: ViewNode, foreground: HexColor?, backdrop: HexColor?, labeled: Bool, into found: inout [String]) {
        var foreground = foreground, backdrop = backdrop, labeled = labeled
        switch node {
        case .styled(let child, let style):
            if case .color(let color)? = style.foreground { foreground = color }
            if style.accessibilityLabel != nil { labeled = true }
            // Text is read against this node's background, or, when it sets
            // a color of its own, against what is behind it.
            let behind: [HexColor] = style.background.map { colors(of: $0.paint) } ?? (style.foreground != nil ? [backdrop ?? HexColor("#00000000")] : [])
            if let text = foreground, !child.plainText.isEmpty {
                for background in behind {
                    for dark in [false, true] {
                        let front = text.hex(dark: dark), back = opaque(background.hex(dark: dark), over: backdrop, dark: dark)
                        if let ratio = HexColor.contrast(front, back), ratio < minimumContrast {
                            found.append("low contrast \(String(format: "%.1f", ratio)):1 for \(front) on \(back) in \(dark ? "dark" : "light") mode (\"\(child.plainText.prefix(30))\"); aim for \(minimumContrast):1")
                        }
                    }
                }
            }
            if case .color(let color)? = style.background?.paint {
                backdrop = HexColor(opaque(color.light, over: backdrop, dark: false), dark: opaque(color.hex(dark: true), over: backdrop, dark: true))
            }
        case .tappable(let content, let action) where !labeled && content.plainText.isEmpty:
            found.append("button {\(action)} has no text; give it .accessibilityLabel(...)")
        default:
            break
        }
        for child in node.children { walk(child, foreground: foreground, backdrop: backdrop, labeled: labeled, into: &found) }
    }

    /// The panel's own background, which a see-through color sits on:
    /// darker and lighter than the popover material, to err on the side of
    /// a warning.
    static let panelBackground = (light: "#E2E2E2", dark: "#363636")

    /// The hex colors a background shows: one, or each stop of a gradient.
    /// A material shows what is behind it, so it is checked as the backdrop
    /// it sits on (the panel when nothing else is behind).
    private static func colors(of paint: Paint) -> [HexColor] {
        paint.stops
    }

    /// A `#RRGGBBAA` color as it looks over `backdrop`, or over the panel.
    static func opaque(_ hex: String, over backdrop: HexColor?, dark: Bool) -> String {
        guard let color = HexColor.components(hex), color.alpha < 1,
              let under = HexColor.components(backdrop?.hex(dark: dark) ?? (dark ? panelBackground.dark : panelBackground.light)) else { return hex }
        func channel(_ top: Double, _ bottom: Double) -> String {
            String(format: "%02X", Int(((top * color.alpha + bottom * (1 - color.alpha)) * 255).rounded()))
        }
        return "#" + channel(color.red, under.red) + channel(color.green, under.green) + channel(color.blue, under.blue)
    }
}
