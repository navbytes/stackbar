import Foundation
import StackbarProtocol

/// What happens when someone starts a command, from anywhere: the palette,
/// an alias or fallback, a hotkey, a typed keyword, a `stackbar://` link,
/// Spotlight or Shortcuts, or a notification button. Each of those only
/// carries out the plan, so they all treat a command the same way.
public enum CommandStart {
    public enum Plan: Equatable, Sendable {
        /// Run it now with these arguments, defaults filled in.
        case run(arguments: [String: String])
        /// Show its argument fields with these values filled in.
        case ask(arguments: [String: String])
        /// Open its view with this search text and these arguments.
        case openView(CommandQuery)
        /// Don't start it; say this instead.
        case refuse(String)

        /// Whether the command would start: anything but a refusal.
        public var starts: Bool {
            if case .refuse = self { return false }
            return true
        }
    }

    /// The plan for `entry` started from `source`.
    ///
    /// - `arguments` are values the caller already has (a link's query
    ///   string, a plugin's `navigate`, a notification button's).
    /// - `input` is free text typed after the command (an alias, a fallback,
    ///   Spotlight's Input). It fills a run command's first argument and a
    ///   view's search.
    ///
    /// A run command runs once every required argument has a value. Picked
    /// by hand in the palette with nothing filled yet, a command that takes
    /// arguments shows its fields first, so optional ones can be set; any
    /// other source runs it with the defaults.
    public static func plan(_ entry: CommandRegistry.Entry, preference: CommandPreference = CommandPreference(), source: InvocationSource, arguments: [String: String] = [:], input: String = "") -> Plan {
        let spec = entry.spec
        if let refusal = refusal(spec, enabled: preference.enabled, source: source) { return .refuse(refusal) }
        let input = input.trimmingCharacters(in: .whitespaces)
        switch spec.kind {
        case .view:
            return .openView(CommandQuery(text: input, arguments: filled(spec, arguments)))
        case .run:
            var given = arguments
            if !input.isEmpty, let first = spec.arguments.first, (given[first.name] ?? "").isEmpty {
                given[first.name] = input
            }
            let values = filled(spec, given)
            let ready = spec.requiredArguments.allSatisfy { !(values[$0.name] ?? "").isEmpty }
            let pickedWithNothing = source == .palette && !spec.arguments.isEmpty && given.values.allSatisfy(\.isEmpty)
            return ready && !pickedWithNothing ? .run(arguments: values) : .ask(arguments: values)
        }
    }

    /// Why `source` may not start the command, or nil when it may.
    /// A command kept inside Stackbar can't be started from outside it, and
    /// one switched off in Settings can't be started by a shortcut, keyword,
    /// link or Spotlight. The palette and a plugin's own buttons only offer
    /// commands that are switched on.
    public static func refusal(_ spec: CommandSpec, enabled: Bool = true, source: InvocationSource) -> String? {
        if isOutside(source), spec.exposure == .stackbarOnly {
            return "\(spec.title) can only be run from inside Stackbar"
        }
        if !enabled, isOutside(source) || source == .hotkey {
            return "\(spec.title) is switched off in Stackbar's settings"
        }
        return nil
    }

    /// The arguments with each empty one set to its default, or a choice's
    /// first option.
    public static func filled(_ spec: CommandSpec, _ arguments: [String: String]) -> [String: String] {
        var values = arguments
        for argument in spec.arguments where (values[argument.name] ?? "").isEmpty {
            values[argument.name] = argument.defaultValue ?? argument.options?.first ?? ""
        }
        return values
    }

    /// The first required argument still empty, for "needs …".
    public static func missing(_ spec: CommandSpec, _ arguments: [String: String]) -> ArgumentSpec? {
        spec.requiredArguments.first { (arguments[$0.name] ?? "").isEmpty }
    }

    private static func isOutside(_ source: InvocationSource) -> Bool {
        source == .link || source == .spotlight || source == .shortcuts || source == .cli
    }
}
