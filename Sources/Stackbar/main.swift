#if os(macOS)
import AppKit

// The Stackbar menu-bar app. Everything interesting lives in StackbarHostCore; this
// target is the AppKit/SwiftUI shell around it.
import StackbarHostCore

let app = NSApplication.shared
// Before anything opens a file there: bring over a Mac's data from when the
// app was called Fluid.
StackbarPaths.migrateFromFluid()
// One Stackbar per user: a second copy would take over the agent socket and
// run every plugin twice.
guard let instanceLock = InstanceLock.acquire(StackbarPaths.instanceLockFile) else {
    app.setActivationPolicy(.accessory)
    let alert = NSAlert()
    alert.messageText = "Stackbar is already running"
    alert.informativeText = "Look for it in the menu bar. Quit that copy first to start a new one."
    alert.runModal()
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
#else
import Foundation

print("The Stackbar app runs on macOS. On this platform, use stackbarctl to build and render plugins.")
#endif
