// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HolyMacBook",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "HolyMacBook",
            path: "Sources/HolyMacBook"
        )
    ]
)
