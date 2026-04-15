// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "XPCMapping",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "XPCMapping", targets: ["XPCMapping"])
    ],
    dependencies: [
        .package(path: "../EngineInterface"),
        .package(path: "../PlannerCore")
    ],
    targets: [
        .target(
            name: "XPCMapping",
            dependencies: ["EngineInterface", "PlannerCore"],
            path: "Sources/XPCMapping"
        ),
        .testTarget(
            name: "XPCMappingTests",
            dependencies: ["XPCMapping", "EngineInterface", "PlannerCore"],
            path: "Tests/XPCMappingTests"
        )
    ]
)
