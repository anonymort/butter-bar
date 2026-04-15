// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PlannerCore",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "PlannerCore", targets: ["PlannerCore"])
    ],
    targets: [
        .target(
            name: "PlannerCore",
            path: "Sources/PlannerCore"
        ),
        .testTarget(
            name: "PlannerCoreTests",
            dependencies: ["PlannerCore"],
            path: "Tests/PlannerCoreTests"
        )
    ]
)
