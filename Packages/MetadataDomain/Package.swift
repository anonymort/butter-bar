// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MetadataDomain",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "MetadataDomain", targets: ["MetadataDomain"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MetadataDomain",
            dependencies: [],
            path: "Sources/MetadataDomain",
            exclude: ["TMDBSecrets.local.swift.example"]
        ),
        .testTarget(
            name: "MetadataDomainTests",
            dependencies: ["MetadataDomain"],
            path: "Tests/MetadataDomainTests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
