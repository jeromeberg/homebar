// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HomeBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "HomeBar", targets: ["HomeBar"])],
    targets: [
        .target(name: "HomeBarCore"),
        .executableTarget(name: "HomeBar", dependencies: ["HomeBarCore"]),
        .testTarget(name: "HomeBarCoreTests", dependencies: ["HomeBarCore"])
    ]
)
