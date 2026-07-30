// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PalMac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PalMacKit", targets: ["PalMacKit"]),
        .executable(name: "palmac", targets: ["PalMac"]),
        .executable(name: "PalMacApp", targets: ["PalMacApp"])
    ],
    targets: [
        .target(
            name: "PalMacKit",
            path: "Sources/PalMacKit"
        ),
        .executableTarget(
            name: "PalMac",
            dependencies: ["PalMacKit"],
            path: "Sources/PalMac"
        ),
        .executableTarget(
            name: "PalMacApp",
            dependencies: ["PalMacKit"],
            path: "Sources/PalMacApp"
        ),
        .testTarget(
            name: "PalMacTests",
            dependencies: ["PalMacKit"],
            path: "Tests/PalMacTests"
        )
    ]
)
