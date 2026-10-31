#if os(macOS)
import AppKit

// The Fluid menu-bar app. Everything interesting lives in FluidHostCore; this
// target is the AppKit/SwiftUI shell around it.
import FluidHostCore

let app = NSApplication.shared
// One Fluid per user: a second copy would take over the agent socket and
// run every plugin twice.
guard let instanceLock = InstanceLock.acquire(FluidPaths.instanceLockFile) else {
    app.setActivationPolicy(.accessory)
    let alert = NSAlert()
    alert.messageText = "Fluid is already running"
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

print("The Fluid app runs on macOS. On this platform, use fluidctl to build and render plugins.")
#endif
