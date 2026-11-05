// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ListingPolish",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ListingPolish", targets: ["ListingPolish"]),
        .library(name: "ListingPolishCore", targets: ["ListingPolishCore"]),
    ],
    targets: [
        // Pure Swift logic: models, pricing, prompts, API request/response. No AppKit.
        .target(name: "ListingPolishCore"),
        // The macOS SwiftUI app.
        .executableTarget(
            name: "ListingPolish",
            dependencies: ["ListingPolishCore"]
        ),
        .testTarget(
            name: "ListingPolishCoreTests",
            dependencies: ["ListingPolishCore"]
        ),
    ]
)
