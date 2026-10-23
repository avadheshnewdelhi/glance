// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Glance",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "GlanceCore"),
        .executableTarget(name: "Glance", dependencies: ["GlanceCore"]),
        .testTarget(name: "GlanceCoreTests", dependencies: ["GlanceCore"]),
    ]
)
