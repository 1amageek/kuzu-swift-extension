// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "kuzu-swift-extension",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .macCatalyst(.v17)
    ],
    products: [
        .library(
            name: "KuzuSwiftExtension",
            targets: ["KuzuSwiftExtension"]),
        .library(
            name: "KuzuSwiftMacros",
            targets: ["KuzuSwiftMacros"]),
        .library(
            name: "KuzuSwiftProtocols",
            targets: ["KuzuSwiftProtocols"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
        .package(url: "https://github.com/kuzudb/kuzu-swift.git", from: "0.11.1"),
        .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.2.1")
    ],
    targets: [
        // Protocol definitions
        .target(
            name: "KuzuSwiftProtocols",
            dependencies: []
        ),
        
        // Main library target
        .target(
            name: "KuzuSwiftExtension",
            dependencies: [
                "KuzuSwiftMacros",
                "KuzuSwiftProtocols",
                .product(name: "Kuzu", package: "kuzu-swift"),
                .product(name: "Algorithms", package: "swift-algorithms")
            ]
        ),
        
        // Macro implementations
        .macro(
            name: "KuzuSwiftMacrosPlugin",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),
        
        // Macro declarations and exports
        .target(
            name: "KuzuSwiftMacros",
            dependencies: [
                "KuzuSwiftMacrosPlugin",
                "KuzuSwiftProtocols"
            ]
        ),
        
        // Test targets
        .testTarget(
            name: "KuzuSwiftExtensionTests",
            dependencies: [
                "KuzuSwiftExtension",
                .product(name: "Kuzu", package: "kuzu-swift")
            ]
        ),
        .testTarget(
            name: "KuzuSwiftMacrosTests",
            dependencies: [
                "KuzuSwiftMacrosPlugin",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
