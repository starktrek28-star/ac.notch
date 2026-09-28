// swift-tools-version:5.7
import PackageDescription

var targets: [Target] = [
    // The correction engine: plain Swift + Foundation, so it builds and tests anywhere.
    .target(name: "ACNotchEngine", path: "Sources/ACNotchEngine"),
    // Scores the engine on the typo benchmark (Benchmark/data).
    .executableTarget(name: "acbench", dependencies: ["ACNotchEngine"], path: "Sources/acbench"),
    .testTarget(name: "ACNotchEngineTests", dependencies: ["ACNotchEngine"], path: "Tests/ACNotchEngineTests"),
]
var products: [Product] = [.executable(name: "acbench", targets: ["acbench"])]

#if os(macOS)
// The app itself needs AppKit, so it only builds on a Mac.
targets.append(.executableTarget(name: "ACNotch", dependencies: ["ACNotchEngine"], path: "Sources/ACNotch"))
products.append(.executable(name: "ACNotch", targets: ["ACNotch"]))
#endif

let package = Package(
    name: "ACNotch",
    platforms: [.macOS(.v12)],
    products: products,
    targets: targets
)
