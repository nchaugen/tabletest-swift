// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "tabletest-swift",
    products: [
        .library(name: "TableTestParser", targets: ["TableTestParser"]),
    ],
    targets: [
        .target(name: "TableTestParser"),
        .testTarget(
            name: "TableTestParserTests",
            dependencies: ["TableTestParser"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
