// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "ACNotch",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(name: "ACNotch", path: "Sources/ACNotch")
    ]
)
