// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Frame",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Frame", targets: ["Frame"])],
    targets: [
        .target(name: "FrameCore"),
        .executableTarget(name: "Frame", dependencies: ["FrameCore"]),
        .executableTarget(name: "FrameChecks", dependencies: ["FrameCore"], path: "Tests/FrameCoreTests")
    ]
)
