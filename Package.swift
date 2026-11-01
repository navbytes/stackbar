// swift-tools-version: 6.2
import PackageDescription

// Stackbar — a native macOS host for live, AI-written Swift plugins. The successor
// to Vee for developers who want apps, not scripts (see README.md).
//
// The Foundation-only targets (StackbarProtocol, StackbarKit, StackbarHostCore,
// stackbarctl, the examples) build and test on Linux too, so the plugin contract
// and the supervisor are exercised without a Mac. The `Stackbar` app target is
// AppKit/SwiftUI and compiles to a stub everywhere else.
let package = Package(
    name: "Stackbar",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "StackbarProtocol", targets: ["StackbarProtocol"]),
        .library(name: "StackbarKit", targets: ["StackbarKit"]),
        .library(name: "StackbarHostCore", targets: ["StackbarHostCore"]),
        .library(name: "StackbarUI", targets: ["StackbarUI"]),
        .executable(name: "Stackbar", targets: ["Stackbar"]),
        .executable(name: "stackbarctl", targets: ["stackbarctl"]),
    ],
    targets: [
        // The wire contract between a plugin and the host: the view tree, the
        // manifest, and the messages. Shared by both sides, depends on nothing.
        .target(name: "StackbarProtocol"),
        // What a plugin imports: the SwiftUI-like DSL and the runtime loop that
        // speaks StackbarProtocol over the plugin's stdin/stdout.
        .target(name: "StackbarKit", dependencies: ["StackbarProtocol"]),
        // The host's UI-free core: building, supervising and talking to plugins.
        .target(name: "StackbarHostCore", dependencies: ["StackbarProtocol"]),
        // The SwiftUI renderers for every surface, shared by the app, the
        // widget and stackbarctl's PNG snapshots. Empty on Linux.
        .target(name: "StackbarUI", dependencies: ["StackbarProtocol"]),
        .executableTarget(name: "Stackbar", dependencies: ["StackbarProtocol", "StackbarHostCore", "StackbarUI"]),
        .executableTarget(name: "stackbarctl", dependencies: ["StackbarHostCore", "StackbarUI"]),
        .executableTarget(name: "ClockPlugin", dependencies: ["StackbarKit"], path: "Examples/ClockPlugin"),
        .executableTarget(name: "PRCockpitPlugin", dependencies: ["StackbarKit"], path: "Plugins/PRCockpitPlugin"),
        .executableTarget(name: "PomodoroPlugin", dependencies: ["StackbarKit"], path: "Examples/PomodoroPlugin"),
        .executableTarget(name: "TodoPlugin", dependencies: ["StackbarKit"], path: "Examples/TodoPlugin"),
        .executableTarget(name: "WeatherPlugin", dependencies: ["StackbarKit"], path: "Examples/WeatherPlugin"),
        .executableTarget(name: "CIStatusPlugin", dependencies: ["StackbarKit"], path: "Examples/CIStatusPlugin"),
        // First-party plugins (Plugins/), shipped with the app. Examples/ are
        // the small teaching ones.
        .executableTarget(name: "ClipboardPlugin", dependencies: ["StackbarKit"], path: "Plugins/ClipboardPlugin"),
        .executableTarget(name: "StayAwakePlugin", dependencies: ["StackbarKit"], path: "Plugins/StayAwakePlugin"),
        .executableTarget(name: "UpNextPlugin", dependencies: ["StackbarKit"], path: "Plugins/UpNextPlugin"),
        .executableTarget(name: "QuicklinksPlugin", dependencies: ["StackbarKit"], path: "Plugins/QuicklinksPlugin"),
        // A plugin that misbehaves on request, so the supervisor's crash and
        // restart handling is tested against a real process.
        .executableTarget(name: "FixturePlugin", dependencies: ["StackbarKit"], path: "Tests/Fixtures/FixturePlugin"),
        .testTarget(name: "StackbarProtocolTests", dependencies: ["StackbarProtocol"]),
        .testTarget(name: "StackbarKitTests", dependencies: ["StackbarKit"]),
        .testTarget(name: "StackbarHostCoreTests", dependencies: ["StackbarHostCore", "ClockPlugin", "FixturePlugin", "PomodoroPlugin", "TodoPlugin", "ClipboardPlugin", "StayAwakePlugin", "UpNextPlugin", "QuicklinksPlugin"]),
    ]
)
