// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClaudeUsageDashboard",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ClaudeUsageDashboard",
            path: "Sources/ClaudeUsageDashboard"
        )
    ]
)
