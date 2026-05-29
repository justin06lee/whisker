// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Whisker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Whisker",
            path: "Sources/Whisker",
            resources: [.copy("Resources/menubar.png"), .copy("Resources/appicon.png")]
        ),
        .testTarget(
            name: "WhiskerTests",
            dependencies: ["Whisker"],
            path: "Tests/WhiskerTests"
        ),
    ]
)
