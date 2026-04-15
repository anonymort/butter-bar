// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EngineStore",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "EngineStore", targets: ["EngineStore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "EngineStore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/EngineStore"
        ),
        .testTarget(
            name: "EngineStoreTests",
            dependencies: [
                "EngineStore",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Tests/EngineStoreTests"
        )
    ]
)
