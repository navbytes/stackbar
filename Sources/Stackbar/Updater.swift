#if os(macOS)
import AppKit
import Observation
#if canImport(Sparkle)
import Sparkle
#endif

/// Self-update through Sparkle. Only the release build carries Sparkle and
/// the public key it checks the appcast with; `swift build`, bundle.sh and
/// forks get an updater that says where updates come from instead.
@MainActor @Observable
final class Updater: NSObject {
    /// Whether this build can update itself.
    private(set) var isAvailable = false
    private(set) var canCheck = false

    #if canImport(Sparkle)
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    #endif

    override init() {
        super.init()
        #if canImport(Sparkle)
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.isEmpty else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        isAvailable = true
        canCheck = controller.updater.canCheckForUpdates
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheck = value }
        }
        #endif
    }

    /// Whether Sparkle looks for updates once a day by itself.
    var checksAutomatically: Bool {
        get {
            access(keyPath: \.checksAutomatically)
            #if canImport(Sparkle)
            return controller?.updater.automaticallyChecksForUpdates ?? false
            #else
            return false
            #endif
        }
        set {
            withMutation(keyPath: \.checksAutomatically) {
                #if canImport(Sparkle)
                controller?.updater.automaticallyChecksForUpdates = newValue
                #endif
            }
        }
    }

    /// What Settings says when this build can't update itself.
    static let unavailableNote = "This build doesn't update itself. Update with Homebrew (brew upgrade --cask stackbar) or download the latest release from stackbar.app."

    @objc func checkForUpdates(_ sender: Any?) {
        #if canImport(Sparkle)
        if let controller {
            NSApp.activate()
            controller.checkForUpdates(sender)
            return
        }
        #endif
        if let url = URL(string: "https://github.com/navbytes/stackbar/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }
}

#if canImport(Sparkle)
extension Updater: SPUStandardUserDriverDelegate {
    /// Stackbar has no Dock icon, so Sparkle's scheduled reminder would open
    /// behind other apps. Bring Stackbar forward first.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        Task { @MainActor in NSApp.activate() }
    }
}
#endif
#endif
