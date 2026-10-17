// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeepAliveCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KeepAliveCore", targets: ["KeepAliveCore"]),
    ],
    targets: [
        .target(name: "KeepAliveCore"),
        // L1: pure logic, no hardware.
        .testTarget(name: "KeepAliveCoreTests", dependencies: ["KeepAliveCore"]),
        // L2: real CoreAudio and IOKit against the BlackHole virtual device.
        .testTarget(name: "KeepAliveIntegrationTests", dependencies: ["KeepAliveCore"]),
    ]
)
