// Read-only probes for mac-smoke.sh; none of these show a permission prompt.
//   ax                      prints yes/no: this process is trusted for Accessibility
//   automation <bundle id>  prints granted/denied/undetermined/not-running for Apple events
//   windows <owner>         prints "<layer> <name>" for each on-screen window the owner has
import ApplicationServices
import CoreGraphics
import Foundation

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "ax":
    print(AXIsProcessTrusted() ? "yes" : "no")
case "automation":
    var target = AEAddressDesc()
    let id = Array(args.dropFirst().first!.utf8)
    AECreateDesc(typeApplicationBundleID, id, id.count, &target)
    let status = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false)
    AEDisposeDesc(&target)
    switch status {
    case noErr: print("granted")
    case OSStatus(errAEEventNotPermitted): print("denied")
    case OSStatus(errAEEventWouldRequireUserConsent): print("undetermined")
    case OSStatus(procNotFound): print("not-running")
    default: print("status \(status)")
    }
case "windows":
    let owner = args.dropFirst().first!
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for window in list where window[kCGWindowOwnerName as String] as? String == owner {
        print("\(window[kCGWindowLayer as String] ?? "?") \(window[kCGWindowName as String] ?? "")")
    }
default:
    print("usage: mac-smoke-probe ax | automation <bundle id> | windows <owner>")
    exit(2)
}
