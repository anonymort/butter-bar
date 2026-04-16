// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PlayerDomain",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "PlayerDomain", targets: ["PlayerDomain"])
    ],
    dependencies: [
        .package(path: "../EngineInterface")
    ],
    targets: [
        .target(
            name: "PlayerDomain",
            dependencies: [
                .product(name: "EngineInterface", package: "EngineInterface")
            ],
            path: "Sources/PlayerDomain"
        ),
        .testTarget(
            name: "PlayerDomainTests",
            dependencies: ["PlayerDomain"],
            path: "Tests/PlayerDomainTests"
        )
    ]
)
