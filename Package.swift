// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClipboardManager",
    platforms: [
        .macOS(.v15)
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
