// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LibraryDomain",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "LibraryDomain", targets: ["LibraryDomain"])
    ],
    dependencies: [
        .package(path: "../EngineInterface")
    ],
    targets: [
        .target(
            name: "LibraryDomain",
            dependencies: [
                .product(name: "EngineInterface", package: "EngineInterface")
            ],
            path: "Sources/LibraryDomain"
        ),
        .testTarget(
            name: "LibraryDomainTests",
            dependencies: ["LibraryDomain"],
            path: "Tests/LibraryDomainTests"
        )
    ]
)
