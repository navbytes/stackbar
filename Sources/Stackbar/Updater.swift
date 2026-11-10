#if os(macOS)
import AppKit
import Observation
import StackbarHostCore
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
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        isAvailable = true
        canCheck = controller.updater.canCheckForUpdates
        // Sparkle changes this on the main thread.
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.canCheck = self?.controller?.updater.canCheckForUpdates ?? false }
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

    /// Whether updates come from the beta feed, which also has pre-releases.
    nonisolated static let betaKey = "betaUpdates"
    /// Nil when the build's distribution has no beta feed.
    nonisolated static var betaFeed: String? { Distribution.current.updates.betaFeed?.absoluteString }

    var getsBetas: Bool {
        get {
            access(keyPath: \.getsBetas)
            return UserDefaults.standard.bool(forKey: Self.betaKey)
        }
        set {
            withMutation(keyPath: \.getsBetas) {
                UserDefaults.standard.set(newValue, forKey: Self.betaKey)
            }
            #if canImport(Sparkle)
            // Look now, so turning betas on finds the current one.
            if newValue { controller?.updater.checkForUpdatesInBackground() }
            #endif
        }
    }

    /// What Settings says when this build can't update itself.
    static var unavailableNote: String { Distribution.current.updates.manualNote }

    @objc func checkForUpdates(_ sender: Any?) {
        #if canImport(Sparkle)
        if let controller {
            NSApp.activate()
            controller.checkForUpdates(sender)
            return
        }
        #endif
        NSWorkspace.shared.open(Distribution.current.latestReleaseURL)
    }
}

#if canImport(Sparkle)
extension Updater: SPUUpdaterDelegate {
    /// The beta feed when Get beta versions is on; nil keeps SUFeedURL.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        UserDefaults.standard.bool(forKey: Updater.betaKey) ? Updater.betaFeed : nil
    }
}

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
