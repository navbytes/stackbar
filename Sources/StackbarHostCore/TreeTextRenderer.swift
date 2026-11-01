import Foundation
import StackbarProtocol

/// Draws a view tree as plain text: for `stackbarctl render`, for tests, and for
/// an agent that wants to read what a plugin shows without a screen.
///
/// Action ids are printed next to the controls that carry them, so the output
/// doubles as a list of what `stackbarctl render --event <id>` can press.
public enum TreeTextRenderer {
    /// `now` is the moment timers and timed progress are read at.
    public static func render(_ node: ViewNode, showActions: Bool = true, now: Date = Date()) -> String {
        lines(node, depth: 0, showActions: showActions, now: now).joined(separator: "\n")
    }

    static func lines(_ node: ViewNode, depth: Int, showActions: Bool, now: Date) -> [String] {
        let pad = String(repeating: "  ", count: depth)
        func tag(_ id: ActionID) -> String { showActions ? "  {\(id)}" : "" }

        switch node {
        case .text(let string, let style, let role):
            let body = style == .title ? "# \(string)" : string
            return [pad + body + roleSuffix(role)]
        case .label(let title, let symbol, let role):
            return [pad + "[\(symbol)] \(title)" + roleSuffix(role)]
        case .stack(.horizontal, _, _, let children):
            let parts = children.map { lines($0, depth: 0, showActions: showActions, now: now).joined(separator: " ") }.filter { !$0.isEmpty }
            return [pad + parts.joined(separator: "  ")]
        case .stack(.vertical, _, _, let children), .stack(.depth, _, _, let children), .grid(_, _, let children):
            return children.flatMap { lines($0, depth: depth, showActions: showActions, now: now) }
        case .list(let searchable, let children):
            let header = pad + (searchable ? "List (searchable)" : "List")
            return [header] + children.flatMap { lines($0, depth: depth + 1, showActions: showActions, now: now) }
        case .section(let title, let children):
            let header = pad + "-- \(title ?? "") --"
            return [header] + children.flatMap { lines($0, depth: depth, showActions: showActions, now: now) }
        case .row(let row):
            var line = pad + "* " + row.title
            if let subtitle = row.subtitle { line += " - \(subtitle)" }
            for accessory in row.accessories {
                line += "  " + lines(accessory, depth: 0, showActions: showActions, now: now).joined(separator: " ")
            }
            if !row.actions.isEmpty {
                let actions = row.actions.map { action in
                    action.title + (action.shortcut.map { " (\($0))" } ?? "") + (action.navigate.map { " -> \($0.command)" } ?? tag(action.id))
                }
                line += "  <" + actions.joined(separator: ", ") + ">"
            }
            return [line]
        case .badge(let text, let role):
            return [pad + "[\(text)]" + roleSuffix(role)]
        case .button(let title, _, let role, let action):
            return [pad + "(\(title))" + roleSuffix(role) + tag(action)]
        case .toggle(let title, let isOn, let action):
            return [pad + (isOn ? "[x] " : "[ ] ") + title + tag(action)]
        case .progress(let value, let total, let label, _, _, let timing):
            let fraction = timing?.fraction(at: now) ?? (total > 0 ? min(1, max(0, value / total)) : 0)
            let filled = Int((fraction * 10).rounded())
            let bar = String(repeating: "#", count: filled) + String(repeating: ".", count: 10 - filled)
            return [pad + (label.map { "\($0) " } ?? "") + "[\(bar)] \(Int((fraction * 100).rounded()))%"]
        case .divider:
            return [pad + "----"]
        case .labeled(let label, let value, let role):
            return [pad + "\(label): \(value)" + roleSuffix(role)]
        case .chart(let values, let kind, let label, _, let options):
            if kind == .donut {
                let names = options?.labels ?? []
                let total = values.reduce(0, +)
                let parts = values.enumerated().map { index, value in
                    "\(index < names.count ? names[index] : "#\(index + 1)") \(ChartNumber.format(value))\(options?.unit ?? "")"
                        + (total > 0 ? String(format: " (%.1f%%)", value / total * 100) : "")
                }
                return [pad + (label.map { "\($0): " } ?? "") + parts.joined(separator: ", ") + " (donut)"]
            }
            if kind == .heatmap {
                let peak = values.indices.max { values[$0] < values[$1] }
                let busiest = peak.map { index in
                    ", busiest " + ((options?.labels).flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? "day \(index + 1)") + " \(ChartNumber.format(values[index]))\(options?.unit ?? "")"
                } ?? ""
                return [pad + (label.map { "\($0) " } ?? "") + sparkline(values) + " (heatmap: \(values.count) days, \(values.filter { $0 > 0 }.count) active\(busiest))"]
            }
            let names = options?.labels.map { " [" + $0.joined(separator: " ") + "]" } ?? ""
            return [pad + (label.map { "\($0) " } ?? "") + sparkline(values) + (kind == .line ? "" : " (\(kind.rawValue))") + names]
        case .textField(let placeholder, let text, let action):
            return [pad + "[\(text.isEmpty ? placeholder : text)____]" + tag(action)]
        case .picker(let title, let options, let selection, _, let action):
            let choices = options.map { $0 == selection ? "*\($0)*" : $0 }.joined(separator: " | ")
            return [pad + "\(title): \(choices)" + tag(action)]
        case .slider(let title, let value, let min, let max, _, let action):
            return [pad + "\(title): \(format(value)) (\(format(min))...\(format(max)))" + tag(action)]
        case .link(let title, let url):
            return [pad + "<\(title)> \(url)"]
        case .empty(let title, let symbol, let message):
            return [pad + (symbol.map { "[\($0)] " } ?? "") + title + (message.map { " - \($0)" } ?? "")]
        case .form(let form):
            var result = [pad + "Form"]
            for field in form.fields {
                result.append(pad + "  " + fieldLine(field))
                if let error = field.error { result.append(pad + "    ! \(error)") }
            }
            result.append(pad + "  (\(form.submitTitle))" + tag(form.action))
            return result
        case .styled(let child, let style):
            if let label = style.accessibilityLabel {
                // The label names the child; its actions stay pressable.
                if case .tappable(_, let action) = child { return [pad + "(\(label))" + tag(action)] }
                return [pad + label + child.actions.map(tag).joined()]
            }
            return lines(child, depth: depth, showActions: showActions, now: now)
        case .shape, .spacer:
            return []
        case .image(.symbol(let symbol)):
            return [pad + "[\(symbol)]"]
        case .image(.url):
            return [pad + "[image]"]
        case .timer(let range, let countsDown):
            return [pad + range.clock(at: now, countsDown: countsDown)]
        case .tappable(let content, let action):
            return [pad + "(\(content.plainText))" + tag(action)]
        }
    }

    static func fieldLine(_ field: FormField) -> String {
        let value: String
        switch field.value {
        case .text(let text)?: value = text
        case .bool(let flag)?: value = flag ? "on" : "off"
        case .number(let number)?: value = format(number)
        case .fields?, nil: value = ""
        }
        switch field.kind {
        case .text(let placeholder), .multiline(let placeholder):
            let shown = value.isEmpty ? (placeholder ?? "") : value.replacingOccurrences(of: "\n", with: "⏎")
            return "\(field.label) <\(field.name)>: [\(shown)____]" + (field.kind == .multiline(placeholder: placeholder) ? " (multi-line)" : "")
        case .application:
            return "\(field.label) <\(field.name)>: [app: \(value.isEmpty ? "none" : value)]"
        case .picker(let options):
            return "\(field.label) <\(field.name)>: " + options.map { $0 == value ? "*\($0)*" : $0 }.joined(separator: " | ")
        case .toggle:
            return (value == "on" ? "[x] " : "[ ] ") + "\(field.label) <\(field.name)>"
        }
    }

    /// Eight-level block characters, scaled between the series' min and max.
    public static func sparkline(_ values: [Double]) -> String {
        guard let low = values.min(), let high = values.max() else { return "" }
        let blocks = Array("▁▂▃▄▅▆▇█")
        let span = high - low
        return String(values.map { value in
            span == 0 ? blocks[3] : blocks[min(7, Int(((value - low) / span * 7).rounded()))]
        })
    }

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }

    private static func roleSuffix(_ role: Role) -> String {
        switch role {
        case .primary, .secondary, .accent: return ""
        case .success, .warning, .critical: return " (\(role.rawValue))"
        }
    }
}
