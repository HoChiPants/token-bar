// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TokenBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TokenBar", targets: ["TokenBar"]),
        .executable(name: "tokenbar-cli", targets: ["TokenBarCLI"]),
        .library(name: "TokenBarCore", targets: ["TokenBarCore"])
    ],
    targets: [
        .target(name: "TokenBarCore"),
        .executableTarget(
            name: "TokenBar",
            dependencies: ["TokenBarCore"]
        ),
        .executableTarget(
            name: "TokenBarCLI",
            dependencies: ["TokenBarCore"]
        ),
        .testTarget(
            name: "TokenBarCoreTests",
            dependencies: ["TokenBarCore"]
        )
    ]
)
