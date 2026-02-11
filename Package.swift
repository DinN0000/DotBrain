// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DotBrain",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .executableTarget(
            name: "DotBrain",
            dependencies: ["ZIPFoundation"],
            path: "Sources",
            resources: [
                .process("../Resources")
            ]
        ),
    ]
)
