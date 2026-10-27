// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FSRMetal",
    platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .visionOS(.v1)],
    products: [
        .library(name: "FSRMetal", targets: ["FSRMetal"]),
        .executable(name: "fsr-metal", targets: ["fsr-metal-cli"])
    ],
    dependencies: [.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")],
    targets: [
        .target(name: "FSRMetal", exclude: ["Shaders"], resources: [.copy("Resources/THIRD-PARTY.txt")],
                plugins: [.plugin(name: "CompileFSRMetalShaders")]),
        .plugin(name: "CompileFSRMetalShaders", capability: .buildTool()),
        .executableTarget(name: "fsr-metal-cli", dependencies: ["FSRMetal", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .testTarget(name: "FSRMetalTests", dependencies: ["FSRMetal"])
    ]
)
