// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Showready",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Showready", targets: ["Showready"]),
        .library(name: "ShowreadyCore", targets: ["ShowreadyCore"]),
    ],
    targets: [
        // Pure Swift logic: models, pricing, prompts, API request/response. No AppKit.
        .target(name: "ShowreadyCore"),
        // The macOS SwiftUI app.
        .executableTarget(
            name: "Showready",
            dependencies: ["ShowreadyCore"]
        ),
        .testTarget(
            name: "ShowreadyCoreTests",
            dependencies: ["ShowreadyCore"]
        ),
    ]
)
