// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ProviderDomain",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "ProviderDomain", targets: ["ProviderDomain"])
    ],
    dependencies: [
        .package(path: "../MetadataDomain")
    ],
    targets: [
        .target(
            name: "ProviderDomain",
            dependencies: [
                .product(name: "MetadataDomain", package: "MetadataDomain")
            ],
            path: "Sources/ProviderDomain"
        ),
        .testTarget(
            name: "ProviderDomainTests",
            dependencies: ["ProviderDomain"],
            path: "Tests/ProviderDomainTests"
        )
    ]
)
