// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SubtitleDomain",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "SubtitleDomain", targets: ["SubtitleDomain"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SubtitleDomain",
            dependencies: [],
            path: "Sources/SubtitleDomain"
        ),
        .testTarget(
            name: "SubtitleDomainTests",
            dependencies: ["SubtitleDomain"],
            path: "Tests/SubtitleDomainTests"
        )
    ]
)
