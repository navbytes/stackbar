#if os(macOS)
import Foundation
import StackbarHostCore
#if canImport(Sentry)
import Sentry
#endif

/// Crash reports through Sentry, only after the user says yes. The release
/// build carries the DSN (`SentryDSN` in Info.plist, from the SENTRY_DSN
/// secret); local and fork builds have none, so they never report.
///
/// A report has the stack, the Stackbar and macOS versions and the Mac
/// model. It never has plugin names, logs, file paths or the computer's name.
@MainActor
enum CrashReports {
    static let allowedKey = "crashReportsAllowed"

    private static var dsn: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String ?? ""
        return value.isEmpty ? nil : value
    }

    /// Whether this build can send reports at all.
    static var isAvailable: Bool {
        #if canImport(Sentry)
        return dsn != nil
        #else
        return false
        #endif
    }

    static var isAllowed: Bool {
        get { UserDefaults.standard.bool(forKey: allowedKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: allowedKey)
            newValue ? start() : stop()
        }
    }

    /// At launch: starts only when the user already said yes.
    static func startIfAllowed() {
        if isAllowed { start() }
    }

    private static var started = false

    private static func start() {
        #if canImport(Sentry)
        guard !started, let dsn else { return }
        started = true
        SentrySDK.start { options in
            options.dsn = dsn
            options.releaseName = "stackbar@\(StackbarVersion.current)"
            options.sendDefaultPii = false
            options.enableAutoBreadcrumbTracking = false
            options.tracesSampleRate = 0
            options.beforeSend = { event in
                event.serverName = nil
                event.user = nil
                event.breadcrumbs = nil
                return event
            }
        }
        #endif
    }

    private static func stop() {
        #if canImport(Sentry)
        guard started else { return }
        started = false
        SentrySDK.close()
        #endif
    }
}
#endif
