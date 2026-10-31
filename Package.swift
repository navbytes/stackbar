// swift-tools-version: 6.2
import PackageDescription

// Fluid — a native macOS host for live, AI-written Swift plugins. The successor
// to Vee for developers who want apps, not scripts (see README.md).
//
// The Foundation-only targets (FluidProtocol, FluidKit, FluidHostCore,
// fluidctl, the examples) build and test on Linux too, so the plugin contract
// and the supervisor are exercised without a Mac. The `Fluid` app target is
// AppKit/SwiftUI and compiles to a stub everywhere else.
let package = Package(
    name: "Fluid",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "FluidProtocol", targets: ["FluidProtocol"]),
        .library(name: "FluidKit", targets: ["FluidKit"]),
        .library(name: "FluidHostCore", targets: ["FluidHostCore"]),
        .library(name: "FluidUI", targets: ["FluidUI"]),
        .executable(name: "Fluid", targets: ["Fluid"]),
        .executable(name: "fluidctl", targets: ["fluidctl"]),
    ],
    targets: [
        // The wire contract between a plugin and the host: the view tree, the
        // manifest, and the messages. Shared by both sides, depends on nothing.
        .target(name: "FluidProtocol"),
        // What a plugin imports: the SwiftUI-like DSL and the runtime loop that
        // speaks FluidProtocol over the plugin's stdin/stdout.
        .target(name: "FluidKit", dependencies: ["FluidProtocol"]),
        // The host's UI-free core: building, supervising and talking to plugins.
        .target(name: "FluidHostCore", dependencies: ["FluidProtocol"]),
        // The SwiftUI renderers for every surface, shared by the app, the
        // widget and fluidctl's PNG snapshots. Empty on Linux.
        .target(name: "FluidUI", dependencies: ["FluidProtocol"]),
        .executableTarget(name: "Fluid", dependencies: ["FluidProtocol", "FluidHostCore", "FluidUI"]),
        .executableTarget(name: "fluidctl", dependencies: ["FluidHostCore", "FluidUI"]),
        .executableTarget(name: "ClockPlugin", dependencies: ["FluidKit"], path: "Examples/ClockPlugin"),
        .executableTarget(name: "PRCockpitPlugin", dependencies: ["FluidKit"], path: "Examples/PRCockpitPlugin"),
        .executableTarget(name: "PomodoroPlugin", dependencies: ["FluidKit"], path: "Examples/PomodoroPlugin"),
        .executableTarget(name: "TodoPlugin", dependencies: ["FluidKit"], path: "Examples/TodoPlugin"),
        .executableTarget(name: "WeatherPlugin", dependencies: ["FluidKit"], path: "Examples/WeatherPlugin"),
        .executableTarget(name: "CIStatusPlugin", dependencies: ["FluidKit"], path: "Examples/CIStatusPlugin"),
        // A plugin that misbehaves on request, so the supervisor's crash and
        // restart handling is tested against a real process.
        .executableTarget(name: "FixturePlugin", dependencies: ["FluidKit"], path: "Tests/Fixtures/FixturePlugin"),
        .testTarget(name: "FluidProtocolTests", dependencies: ["FluidProtocol"]),
        .testTarget(name: "FluidKitTests", dependencies: ["FluidKit"]),
        .testTarget(name: "FluidHostCoreTests", dependencies: ["FluidHostCore", "ClockPlugin", "FixturePlugin", "PomodoroPlugin", "TodoPlugin"]),
    ]
)
