// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "LoopGenerator",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LoopGeneratorCore", targets: ["LoopGeneratorCore"]),
        .executable(name: "LoopGenerator", targets: ["LoopGenerator"])
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
        .testTarget(
            name: "LoopGeneratorCoreTests",
            dependencies: ["LoopGeneratorCore"],
            path: "Tests/LoopGeneratorCoreTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
