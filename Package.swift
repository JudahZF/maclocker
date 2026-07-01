// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacLockerNiri",
    products: [
        .executable(name: "maclocker-niri", targets: ["MacLockerNiriCLI"]),
    ],
    targets: [
        .target(name: "MacLockerNiriCore"),
        .executableTarget(
            name: "MacLockerNiriCLI",
            dependencies: ["MacLockerNiriCore"]
        ),
        .testTarget(
            name: "MacLockerNiriTests",
            dependencies: ["MacLockerNiriCore"]
        ),
    ]
)
