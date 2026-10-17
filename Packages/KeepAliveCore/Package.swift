// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeepAliveCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KeepAliveCore", targets: ["KeepAliveCore"]),
        // Virtual devices and capture for L2 tests and kactl; the app never links it.
        .library(name: "KeepAliveTestSupport", targets: ["KeepAliveTestSupport"]),
    ],
    targets: [
        .target(name: "KeepAliveCore"),
        .target(name: "KeepAliveTestSupport", dependencies: ["KeepAliveCore"]),
        // L1: pure logic, no hardware.
        .testTarget(name: "KeepAliveCoreTests", dependencies: ["KeepAliveCore"]),
        // L2: real CoreAudio and IOKit against the BlackHole virtual device.
        .testTarget(name: "KeepAliveIntegrationTests", dependencies: ["KeepAliveCore", "KeepAliveTestSupport"]),
    ]
)
