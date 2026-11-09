#if os(macOS)
import AppKit
import CoreAudio
import IOKit.ps
import Network
import StackbarHostCore

/// Watches the Mac for the system triggers (protocol 26) and reports each
/// once its burst has settled. Cheap enough to run whether or not a plugin
/// listens: every source is a notification, not a poll.
@MainActor
final class MacSystemEvents {
    private let report: (SystemEvent) -> Void
    private var pending: [SystemEvent: Task<Void, Never>] = [:]
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var path: NWPathMonitor?
    private var lastPath: String?
    private var powerSource: CFRunLoopSource?
    private var lastPower: String?
    private var audioListener: AudioObjectPropertyListenerBlock?

    init(report: @escaping (SystemEvent) -> Void) {
        self.report = report
    }

    func start() {
        let distributed = DistributedNotificationCenter.default()
        for (name, event) in [("com.apple.screenIsLocked", SystemEvent.locked), ("com.apple.screenIsUnlocked", .unlocked),
                              ("com.apple.screensaver.didstart", .locked), ("com.apple.screensaver.didstop", .unlocked)] {
            observe(distributed, NSNotification.Name(name), event)
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification, .sleep)
        observe(workspace, NSWorkspace.didActivateApplicationNotification, .frontApp)
        observe(workspace, NSWorkspace.didMountNotification, .volumes)
        observe(workspace, NSWorkspace.didUnmountNotification, .volumes)
        startNetwork()
        startPower()
        startAudio()
    }

    private func observe(_ center: NotificationCenter, _ name: NSNotification.Name, _ event: SystemEvent) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.happened(event) }
        }
        observers.append((center, token))
    }

    /// Reports the event now, or once it has been quiet for its settle time.
    func happened(_ event: SystemEvent) {
        guard event.settle > .zero else {
            report(event)
            return
        }
        pending[event]?.cancel()
        pending[event] = Task { [weak self] in
            try? await Task.sleep(for: event.settle)
            guard !Task.isCancelled else { return }
            self?.report(event)
        }
    }

    // MARK: Network

    private func startNetwork() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            // The interfaces and status, so a path that only re-announced
            // itself isn't a change.
            let summary = "\(path.status)|" + path.availableInterfaces.map { "\($0.name)" }.joined(separator: ",")
            Task { @MainActor in
                guard let self else { return }
                defer { self.lastPath = summary }
                // The first answer is how things are at launch, not a change.
                guard let last = self.lastPath, last != summary else { return }
                self.happened(.network)
            }
        }
        monitor.start(queue: DispatchQueue(label: "io.navbytes.stackbar.network"))
        path = monitor
    }

    // MARK: Power

    private func startPower() {
        lastPower = Self.powerSourceName()
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let events = Unmanaged<MacSystemEvents>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { events.powerChanged() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSource = source
    }

    /// Battery details change every minute; only a move between battery
    /// and adapter counts.
    private func powerChanged() {
        let now = Self.powerSourceName()
        guard now != lastPower else { return }
        lastPower = now
        happened(.power)
    }

    private static func powerSourceName() -> String? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        return IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
    }

    // MARK: Audio

    private func startAudio() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.happened(.audio) }
        }
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener)
        }
        audioListener = listener
    }
}
#endif
