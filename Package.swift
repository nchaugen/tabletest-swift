// swift-tools-version: 6.0
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "tabletest-swift",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "TableTest", targets: ["TableTest"]),
        .library(name: "TableTestParser", targets: ["TableTestParser"]),
        .library(name: "TableTestFormat", targets: ["TableTestFormat"]),
        .executable(name: "tabletest-format", targets: ["tabletest-format"]),
        .plugin(name: "TableTestFormatPlugin", targets: ["TableTestFormatPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"604.0.0"),
    ],
    targets: [
        .target(name: "TableTestParser"),
        .target(name: "TableTestFormat", dependencies: ["TableTestParser"]),
        .target(
            name: "TableTestSourceFormat",
            dependencies: [
                "TableTestFormat",
                "TableTestSyntax",
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "TableTestSyntax",
            dependencies: [.product(name: "SwiftSyntax", package: "swift-syntax")]
        ),
        .macro(
            name: "TableTestMacros",
            dependencies: [
                "TableTestParser",
                "TableTestSyntax",
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(name: "TableTest", dependencies: ["TableTestMacros", "TableTestParser"]),
        .target(name: "SpecFixtures", dependencies: ["TableTestParser"], path: "Tests/SpecFixtures"),
        .testTarget(
            name: "TableTestTests",
            dependencies: ["TableTest", "SpecFixtures"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "TableTestMacrosTests",
            dependencies: [
                "TableTestMacros",
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "TableTestFormatTests",
            dependencies: ["TableTestFormat", "SpecFixtures"],
            resources: [.copy("Fixtures")]
        ),
        .executableTarget(name: "tabletest-format", dependencies: ["TableTestSourceFormat"]),
        .plugin(
            name: "TableTestFormatPlugin",
            capability: .command(
                intent: .custom(
                    verb: "tabletest-format",
                    description: "Formats the TableTest tables in .swift and .table files"
                ),
                permissions: [
                    .writeToPackageDirectory(reason: "Aligns the columns of the TableTest tables in the sources"),
                ]
            ),
            dependencies: ["tabletest-format"]
        ),
        .testTarget(
            name: "TableTestSourceFormatTests",
            dependencies: ["TableTestSourceFormat"]
        ),
        .testTarget(
            name: "TableTestParserTests",
            dependencies: ["TableTestParser", "SpecFixtures"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
