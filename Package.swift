// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftScript",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SwiftScript",
            targets: ["SwiftScript"]
        ),
        .executable(
            name: "SimpleShell",
            targets: ["SimpleShell"]
        )
    ],
    targets: [
        .target(
            name: "SwiftScript"
        ),
        .executableTarget(
            name: "SimpleShell",
            dependencies: ["SwiftScript"]
        ),
        .testTarget(
            name: "SwiftScriptTests",
            dependencies: ["SwiftScript"]
        )
    ]
)
