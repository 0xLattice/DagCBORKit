// swift-tools-version: 6.0

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "DagCBORKit",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .watchOS(.v8),
        .tvOS(.v15)
    ],
    products: [
        // Reading and writing DAG-CBOR: depends on nothing.
        .library(name: "DagCBORKit", targets: ["DagCBORKit"]),
        // `@DagCBORCodable`, which builds swift-syntax.
        .library(name: "DagCBORMacro", targets: ["DagCBORMacro"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0" ..< "605.0.0"),
    ],
    targets: [
        .target(name: "DagCBORKit"),
        .macro(
            name: "DagCBORMacroPlugin",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(name: "DagCBORMacro", dependencies: ["DagCBORKit", "DagCBORMacroPlugin"]),
        .testTarget(name: "DagCBORKitTests", dependencies: ["DagCBORKit", "DagCBORMacro"]),
        .testTarget(
            name: "DagCBORMacroTests",
            dependencies: [
                "DagCBORMacroPlugin",
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
