// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TestFixtures",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "TestFixtures", targets: ["TestFixtures"])
    ],
    targets: [
        .target(
            name: "TestFixtures",
            path: "Sources/TestFixtures",
            resources: [
                .copy("traces"),
                .copy("expected")
            ]
        ),
        .testTarget(
            name: "TestFixturesTests",
            dependencies: ["TestFixtures"],
            path: "Tests/TestFixturesTests"
        )
    ]
)
