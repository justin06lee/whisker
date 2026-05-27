// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Whisker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Whisker",
            path: "Sources/Whisker"
        ),
        .testTarget(
            name: "WhiskerTests",
            dependencies: ["Whisker"],
            path: "Tests/WhiskerTests"
        ),
    ]
)
