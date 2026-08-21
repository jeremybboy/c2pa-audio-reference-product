// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "LoopGenerator",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LoopGeneratorCore", targets: ["LoopGeneratorCore"]),
        .executable(name: "LoopGenerator", targets: ["LoopGenerator"]),
        .executable(
            name: "LoopGeneratorC2PAVerify",
            targets: ["LoopGeneratorC2PAVerify"]
        )
    ],
    targets: [
        .target(
            name: "LoopGeneratorCore",
            path: "Sources/LoopGeneratorCore"
        ),
        .executableTarget(
            name: "LoopGenerator",
            dependencies: ["LoopGeneratorCore"],
            path: "Sources/LoopGeneratorApp"
        ),
        .executableTarget(
            name: "LoopGeneratorC2PAVerify",
            dependencies: ["LoopGeneratorCore"],
            path: "Sources/LoopGeneratorC2PAVerify"
        ),
        .testTarget(
            name: "LoopGeneratorCoreTests",
            dependencies: ["LoopGeneratorCore"],
            path: "Tests/LoopGeneratorCoreTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
