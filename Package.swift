// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeviceDeck",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DeviceDeck",
            path: "Sources/DeviceDeck",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
