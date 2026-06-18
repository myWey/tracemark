// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TraceMark",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TraceMark", targets: ["TraceMark"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "TraceMark",
            dependencies: [],
            path: "Sources/Screenshot",
            resources: [
                .process("Assets.xcassets"),
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
