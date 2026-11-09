// swift-tools-version: 6.0
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "tabletest-swift",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "TableTest", targets: ["TableTest"]),
        .library(name: "TableTestParser", targets: ["TableTestParser"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"604.0.0"),
    ],
    targets: [
        .target(name: "TableTestParser"),
        .macro(
            name: "TableTestMacros",
            dependencies: [
                "TableTestParser",
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(name: "TableTest", dependencies: ["TableTestMacros", "TableTestParser"]),
        .testTarget(name: "TableTestTests", dependencies: ["TableTest"]),
        .testTarget(
            name: "TableTestMacrosTests",
            dependencies: [
                "TableTestMacros",
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "TableTestParserTests",
            dependencies: ["TableTestParser"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
