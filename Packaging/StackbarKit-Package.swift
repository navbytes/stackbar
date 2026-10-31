// swift-tools-version: 6.2
// The part of Stackbar that plugins build against, bundled inside Stackbar.app.
import PackageDescription

let package = Package(
    name: "StackbarKit",
    platforms: [.macOS("26.0")],
    products: [.library(name: "StackbarKit", targets: ["StackbarKit"])],
    targets: [
        .target(name: "StackbarProtocol"),
        .target(name: "StackbarKit", dependencies: ["StackbarProtocol"]),
    ]
)
