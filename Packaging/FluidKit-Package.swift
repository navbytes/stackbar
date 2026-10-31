// swift-tools-version: 6.2
// The part of Fluid that plugins build against, bundled inside Fluid.app.
import PackageDescription

let package = Package(
    name: "FluidKit",
    platforms: [.macOS("26.0")],
    products: [.library(name: "FluidKit", targets: ["FluidKit"])],
    targets: [
        .target(name: "FluidProtocol"),
        .target(name: "FluidKit", dependencies: ["FluidProtocol"]),
    ]
)
