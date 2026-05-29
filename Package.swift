// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TokenBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TokenBar", targets: ["TokenBar"]),
        .library(name: "TokenBarCore", targets: ["TokenBarCore"])
    ],
    targets: [
        .target(name: "TokenBarCore"),
        .executableTarget(
            name: "TokenBar",
            dependencies: ["TokenBarCore"]
        ),
        .testTarget(
            name: "TokenBarCoreTests",
            dependencies: ["TokenBarCore"]
        )
    ]
)
