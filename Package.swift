// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ping",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Ping",
            path: "Sources/Ping"
        )
    ]
)
