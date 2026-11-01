// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ETS100Tool",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ETS100Tool", targets: ["ETS100Tool"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CZlib",
            linkerSettings: [.linkedLibrary("z")]
        ),
        .target(
            name: "ETS100Core",
            dependencies: ["CZlib"]
        ),
        .target(
            name: "ETS100Tool",
            dependencies: ["ETS100Core"]
        ),
        .testTarget(
            name: "ETS100CoreTests",
            dependencies: ["ETS100Core"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
