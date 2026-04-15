// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EngineInterface",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "EngineInterface", targets: ["EngineInterface"])
    ],
    targets: [
        .target(
            name: "EngineInterface",
            path: "Sources/EngineInterface"
        ),
        .testTarget(
            name: "EngineInterfaceTests",
            dependencies: ["EngineInterface"],
            path: "Tests/EngineInterfaceTests"
        )
    ]
)
