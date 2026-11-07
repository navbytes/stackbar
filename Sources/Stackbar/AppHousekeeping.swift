#if os(macOS)
import AppKit
import Security
import ServiceManagement
import StackbarHostCore

/// Looking after the install itself: moving the app into Applications,
/// putting `stackbarctl` on the PATH, and removing everything Stackbar keeps.
@MainActor
enum AppHousekeeping {
    static let skipMoveKey = "skipMoveToApplications"

    // MARK: Move to Applications

    /// At launch: offers to move the app when it runs from Downloads, a disk
    /// image or a translocated path, unless the user said not to ask.
    static func offerMoveIfNeeded() {
        let bundle = Bundle.main.bundleURL
        #if DEBUG
        return
        #else
        guard !UserDefaults.standard.bool(forKey: skipMoveKey),
              AppLocation.shouldOfferMove(bundlePath: bundle.path, home: NSHomeDirectory()) else { return }
        let alert = NSAlert()
        alert.messageText = "Move Stackbar to Applications?"
        alert.informativeText = "Stackbar is running from \(bundle.deletingLastPathComponent().lastPathComponent). In Applications it can update itself and open at login."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        NSApp.activate()
        let answer = alert.runModal()
        if alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: skipMoveKey) }
        guard answer == .alertFirstButtonReturn else { return }
        move(bundle)
        #endif
    }

    private static func move(_ bundle: URL) {
        let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(bundle.lastPathComponent)
        let files = FileManager.default
        // Copy beside it first, so a failed copy leaves the old one in place.
        let staged = destination.deletingLastPathComponent().appendingPathComponent(".\(bundle.lastPathComponent).moving")
        do {
            try? files.removeItem(at: staged)
            try files.copyItem(at: bundle, to: staged)
            if files.fileExists(atPath: destination.path) {
                try files.trashItem(at: destination, resultingItemURL: nil)
            }
            try files.moveItem(at: staged, to: destination)
        } catch {
            try? files.removeItem(at: staged)
            let alert = NSAlert()
            alert.messageText = "Stackbar couldn't move itself"
            alert.informativeText = "Drag Stackbar into the Applications folder in Finder, then open it from there. (\(error.localizedDescription))"
            alert.runModal()
            return
        }
        // A translocated copy is read-only and goes away on its own.
        if !AppLocation.isTranslocated(bundle.path), !bundle.path.hasPrefix("/Volumes/") {
            try? files.trashItem(at: bundle, resultingItemURL: nil)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: Command-line tool

    /// `stackbarctl` is on the PATH, pointing at this app's copy.
    static var commandLineToolInstalled: Bool {
        let link = AppLocation.commandLineLink
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link) else { return false }
        return URL(fileURLWithPath: target).resolvingSymlinksInPath().path == URL(fileURLWithPath: Platform.stackbarctlPath).resolvingSymlinksInPath().path
    }

    /// Links `stackbarctl` into /usr/local/bin, which asks for an admin
    /// password. Answers the error to show, or nil.
    static func installCommandLineTool() -> String? {
        let tool = Platform.stackbarctlPath
        guard FileManager.default.isExecutableFile(atPath: tool) else { return "This copy of Stackbar has no stackbarctl next to it." }
        let command = AppLocation.linkCommand(to: tool)
        let source = "do shell script \"\(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return nil }
        // -128: the user cancelled the password prompt.
        if (error[NSAppleScript.errorNumber] as? Int) == -128 { return nil }
        return (error[NSAppleScript.errorMessage] as? String) ?? "The link couldn't be made."
    }

    // MARK: Remove all data

    /// Asks, then stops every plugin, moves Stackbar's data, caches and logs
    /// to the Trash, deletes its secrets from the Keychain and its settings,
    /// and quits. The Trash keeps the files until it is emptied.
    static func removeAllData(model: AppModel) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Remove all of Stackbar's data?"
        alert.informativeText = "This moves your plugins, their saved data, the build cache and logs to the Trash, deletes every secret Stackbar keeps in your Keychain, resets its settings and quits. Plugins you wrote stay in the Trash until you empty it."
        alert.addButton(withTitle: "Remove All Data")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { @MainActor in
            await model.stop()
            let files = FileManager.default
            var left: [String] = []
            for folder in [StackbarPaths.dataDirectory, StackbarPaths.cacheDirectory, StackbarPaths.logFile.deletingLastPathComponent()] where files.fileExists(atPath: folder.path) {
                do {
                    try files.trashItem(at: folder, resultingItemURL: nil)
                } catch {
                    left.append(folder.path)
                }
            }
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: KeychainSecretStore().service]
            let deleted = SecItemDelete(query as CFDictionary)
            if deleted != errSecSuccess, deleted != errSecItemNotFound { left.append("the secrets in your Keychain (error \(deleted))") }
            if !left.isEmpty {
                // Say what is still there before quitting, so nobody thinks
                // it is all gone.
                let failed = NSAlert()
                failed.alertStyle = .warning
                failed.messageText = "Some of Stackbar's data couldn't be removed"
                failed.informativeText = "Remove these yourself:\n\n" + left.joined(separator: "\n") + "\n\nEverything else was removed. Stackbar quits now."
                failed.runModal()
            }
            try? await SMAppService.mainApp.unregister()
            if let domain = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: domain) }
            NSApp.terminate(nil)
        }
    }
}
#endif
