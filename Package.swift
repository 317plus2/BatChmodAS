// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BatChmodAS",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BatChmodAS", targets: ["BatChmodAS"])
    ],
    targets: [
        .executableTarget(
            name: "BatChmodAS",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
