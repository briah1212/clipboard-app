// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClipboardManager",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ClipboardManager",
            path: "Sources/ClipboardManager"
        ),
        .testTarget(
            name: "ClipboardManagerTests",
            dependencies: ["ClipboardManager"],
            path: "Tests/ClipboardManagerTests"
        )
    ]
)
