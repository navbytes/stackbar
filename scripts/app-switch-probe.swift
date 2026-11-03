// Measures how reliably a background (accessory) app can bring other apps to
// the front on this Mac, for the rcmd-style switcher spike.
//
//   swiftc -O scripts/app-switch-probe.swift -o /tmp/app-switch-probe
//   /tmp/app-switch-probe auto [trials]     switches between your running apps by itself
//   /tmp/app-switch-probe keys [seconds]    you hold Right ⌘ and press an app's first letter
//
// Each switch is tried with three methods: NSRunningApplication.activate,
// NSWorkspace.openApplication (what a Dock click does), and Accessibility
// (AXFrontmost + AXRaise). `auto` measures each method alone and the
// fallback chain; `keys` runs the chain from inside a real key press, the way
// the switcher would. A switch counts when the target becomes the frontmost app.
import AppKit
import ApplicationServices
import Carbon

setvbuf(stdout, nil, _IOLBF, 0)

enum SwitchMethod: String, CaseIterable {
    case activate, open, ax, chain
}

struct Outcome {
    var app: String
    var method: SwitchMethod
    var won: String?      // the step that landed it, for the chain
    var milliseconds: Int?
    var windows: Int
    var wasHidden: Bool
}

var outcomes: [Outcome] = []
let started = Date()

// MARK: - Apps and windows

func regularApps() -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter {
        $0.activationPolicy == .regular && $0.processIdentifier != getpid() && !$0.isTerminated
    }
}

func name(_ app: NSRunningApplication) -> String { app.localizedName ?? app.bundleIdentifier ?? "pid \(app.processIdentifier)" }

/// Normal-layer windows the app owns, on any Space. Needs no permission.
func windowCount(_ pid: pid_t) -> Int {
    let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.filter {
        ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
    }.count
}

func frontPID() -> pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }

func spin(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

/// Milliseconds until `pid` is frontmost, or nil after `timeout`.
func waitFront(_ pid: pid_t, since start: Date, timeout: Double) -> Int? {
    while Date().timeIntervalSince(start) < timeout {
        if frontPID() == pid { return Int(Date().timeIntervalSince(start) * 1000) }
        spin(0.01)
    }
    return frontPID() == pid ? Int(Date().timeIntervalSince(start) * 1000) : nil
}

// MARK: - The three methods

func viaActivate(_ app: NSRunningApplication) {
    if app.isHidden { app.unhide() }
    app.activate(options: [])
}

func viaOpen(_ app: NSRunningApplication) {
    guard let url = app.bundleURL else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
}

func viaAX(_ app: NSRunningApplication) {
    let element = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    var window: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXMainWindowAttribute as CFString, &window) == .success, let window {
        // swiftlint:disable:next force_cast
        AXUIElementPerformAction(window as! AXUIElement, kAXRaiseAction as CFString)
    }
}

let chainSteps: [(String, (NSRunningApplication) -> Void, Double)] = [
    ("activate", viaActivate, 0.15), ("open", viaOpen, 0.45), ("ax", viaAX, 1.0),
]

// MARK: - Report

func median(_ values: [Int]) -> Int? {
    let sorted = values.sorted()
    return sorted.isEmpty ? nil : sorted[sorted.count / 2]
}

func p95(_ values: [Int]) -> Int? {
    let sorted = values.sorted()
    return sorted.isEmpty ? nil : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
}

func report() {
    print("\n=== app-switch-probe summary ===")
    print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    print("Accessibility trusted: \(AXIsProcessTrusted() ? "yes" : "no")")
    print("Secure Input on now: \(IsSecureEventInputEnabled() ? "yes" : "no")")
    print("Running for \(Int(Date().timeIntervalSince(started)))s, \(outcomes.count) switches")
    for method in SwitchMethod.allCases {
        let rows = outcomes.filter { $0.method == method }
        guard !rows.isEmpty else { continue }
        let wins = rows.compactMap(\.milliseconds)
        let percent = Double(wins.count) / Double(rows.count) * 100
        var line = String(format: "%-9@ %3ld/%3ld landed (%.1f%%)", method.rawValue as NSString, wins.count, rows.count, percent)
        if let median = median(wins), let p95 = p95(wins) { line += "  median \(median)ms  p95 \(p95)ms" }
        print(line)
        if method == .chain {
            let byStep = Dictionary(grouping: rows.compactMap(\.won), by: { $0 }).mapValues(\.count)
            print("          landed by step: \(byStep.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
        }
    }
    let failures = outcomes.filter { $0.milliseconds == nil }
    if !failures.isEmpty {
        print("Misses:")
        for (app, rows) in Dictionary(grouping: failures, by: \.app).sorted(by: { $0.key < $1.key }) {
            let methods = rows.map(\.method.rawValue).joined(separator: ",")
            print("  \(app): \(rows.count) [\(methods)] windows=\(rows[0].windows) hidden=\(rows[0].wasHidden)")
        }
    }
    let noWindows = Set(outcomes.filter { $0.windows == 0 }.map(\.app))
    if !noWindows.isEmpty { print("Apps with no windows (front but nothing to show): \(noWindows.sorted().joined(separator: ", "))") }
    print("Key taps switched off by macOS: \(tapDisabledCount)")
    print("Secure Input seen during the run: \(secureInputSeen ? "yes" : "no")")
}

// MARK: - auto

func runAuto(trials: Int) {
    let original = NSWorkspace.shared.frontmostApplication
    print("Switching \(trials) times between \(regularApps().count) running apps. Hands off the keyboard and mouse.")
    spin(1.5)
    for trial in 0..<trials {
        let candidates = regularApps().filter { $0.processIdentifier != frontPID() }
        guard let target = candidates.randomElement() else { print("Need at least two running apps."); return }
        let method = SwitchMethod.allCases[trial % SwitchMethod.allCases.count]
        var outcome = Outcome(app: name(target), method: method, won: nil, milliseconds: nil,
                              windows: windowCount(target.processIdentifier), wasHidden: target.isHidden)
        let start = Date()
        switch method {
        case .activate: viaActivate(target); outcome.milliseconds = waitFront(target.processIdentifier, since: start, timeout: 1.0)
        case .open: viaOpen(target); outcome.milliseconds = waitFront(target.processIdentifier, since: start, timeout: 1.0)
        case .ax: viaAX(target); outcome.milliseconds = waitFront(target.processIdentifier, since: start, timeout: 1.0)
        case .chain:
            for (step, perform, deadline) in chainSteps {
                perform(target)
                if let milliseconds = waitFront(target.processIdentifier, since: start, timeout: deadline) {
                    outcome.won = step
                    outcome.milliseconds = milliseconds
                    break
                }
            }
        }
        outcomes.append(outcome)
        let result = outcome.milliseconds.map { "ok \($0)ms" } ?? "MISS (front is \(NSWorkspace.shared.frontmostApplication.map(name) ?? "?"))"
        print("[\(trial + 1)/\(trials)] \(method.rawValue) -> \(outcome.app): \(result)\(outcome.won.map { " via \($0)" } ?? "")")
        if IsSecureEventInputEnabled() { secureInputSeen = true }
        spin(0.35)
    }
    if let original { viaActivate(original) }
    spin(0.5)
    report()
}

// MARK: - keys

var tap: CFMachPort?
var tapDisabledCount = 0
var secureInputSeen = false
var rightCommandDown = false
let rightCommandMask: UInt64 = 0x10 // NX_DEVICERCMDKEYMASK

func letter(of event: CGEvent) -> Character? {
    guard let characters = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased(),
          let first = characters.first, first.isLetter else { return nil }
    return first
}

/// Picks the app for a letter: the next app with that first letter after the
/// frontmost one, so pressing again cycles, as rcmd does.
func target(for character: Character) -> NSRunningApplication? {
    let matches = regularApps()
        .filter { name($0).lowercased().first == character }
        .sorted { name($0) < name($1) }
    guard !matches.isEmpty else { return nil }
    if let index = matches.firstIndex(where: { $0.processIdentifier == frontPID() }) {
        return matches[(index + 1) % matches.count]
    }
    return matches[0]
}

final class PendingSwitch {
    let app: NSRunningApplication
    let start = Date()
    var outcome: Outcome

    init(_ app: NSRunningApplication) {
        self.app = app
        outcome = Outcome(app: name(app), method: .chain, won: nil, milliseconds: nil,
                          windows: windowCount(app.processIdentifier), wasHidden: app.isHidden)
    }
}

func switchFromKeyPress(to app: NSRunningApplication) {
    let pending = PendingSwitch(app)
    // Step one runs synchronously inside the key press, which is the case under test.
    viaActivate(app)
    check(pending, step: 0)
}

func check(_ pending: PendingSwitch, step: Int) {
    let (label, _, deadline) = chainSteps[step]
    DispatchQueue.main.asyncAfter(deadline: .now() + deadline) {
        if frontPID() == pending.app.processIdentifier {
            pending.outcome.won = label
            pending.outcome.milliseconds = Int(Date().timeIntervalSince(pending.start) * 1000)
        } else if step + 1 < chainSteps.count {
            chainSteps[step + 1].1(pending.app)
            check(pending, step: step + 1)
            return
        }
        outcomes.append(pending.outcome)
        let result = pending.outcome.milliseconds.map { "ok by \(pending.outcome.won ?? "?") (checked at \($0)ms)" } ?? "MISS"
        print("Right ⌘ -> \(pending.outcome.app): \(result)")
    }
}

func runKeys(seconds: Int) {
    let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
    tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                            eventsOfInterest: CGEventMask(mask), callback: { _, type, event, _ in
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            tapDisabledCount += 1
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            rightCommandDown = event.flags.rawValue & rightCommandMask != 0
        case .keyDown where rightCommandDown:
            guard let character = letter(of: event) else { break }
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
            if let app = target(for: character) {
                switchFromKeyPress(to: app)
            } else {
                print("Right ⌘ \(character): no running app starts with that letter")
            }
            return nil
        case .keyUp where rightCommandDown && letter(of: event) != nil:
            return nil
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }, userInfo: nil)
    guard let tap else {
        print("Could not listen for keys: give Accessibility to the app running this probe (System Settings → Privacy & Security → Accessibility).")
        exit(2)
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    print("Listening for \(seconds)s. Hold RIGHT ⌘ and press an app's first letter; press again to cycle apps on that letter.")
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
        if IsSecureEventInputEnabled(), !secureInputSeen {
            secureInputSeen = true
            print("Secure Input is ON: key listeners are blocked until it goes off.")
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) {
        report()
        exit(0)
    }
    signal(SIGINT) { _ in report(); exit(0) }
    RunLoop.main.run()
}

// MARK: - main

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory) // like Stackbar: a menu-bar app with no Dock icon

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "auto": runAuto(trials: arguments.dropFirst().first.flatMap(Int.init) ?? 120)
case "keys": runKeys(seconds: arguments.dropFirst().first.flatMap(Int.init) ?? 180)
default:
    print("usage: app-switch-probe auto [trials] | keys [seconds]")
    exit(64)
}
