// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Three",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ThreeApp", targets: ["ThreeApp"]),
        .executable(name: "three", targets: ["ThreeCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
    ],
    targets: [
        .target(
            name: "ThreeCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(
            name: "ThreeApp",
            dependencies: ["ThreeCore"]
        ),
        .executableTarget(
            name: "ThreeCLI",
            dependencies: [
                "ThreeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "MCP", package: "swift-sdk"),
            ],
            resources: [.copy("Resources/PlanDay.md"), .copy("Resources/plan-day"), .copy("Resources/CodexPrompt.md")]
        ),
        .testTarget(
            name: "ThreeCoreTests",
            dependencies: ["ThreeCore"]
        ),
        .testTarget(
            name: "ThreeAppTests",
            dependencies: ["ThreeApp"]
        ),
    ]
)
