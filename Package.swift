// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HomeBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "HomeBar", targets: ["HomeBar"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1")
    ],
    targets: [
        .target(name: "HomeBarCore"),
        .executableTarget(
            name: "HomeBar",
            dependencies: ["HomeBarCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "HomeBarCoreTests", dependencies: ["HomeBarCore"]),
        .testTarget(name: "HomeBarTests", dependencies: ["HomeBar"])
    ]
)
