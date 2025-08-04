// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TodoApp",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .executable(name: "TodoCLI", targets: ["TodoCLI"]),
    ],
    dependencies: [
        .package(name: "kuzu-swift-extension", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "TodoCLI",
            dependencies: [
                .product(name: "KuzuSwiftExtension", package: "kuzu-swift-extension")
            ]
        ),
        .target(
            name: "TodoCore",
            dependencies: [
                .product(name: "KuzuSwiftExtension", package: "kuzu-swift-extension")
            ]
        ),
        .testTarget(
            name: "TodoAppTests",
            dependencies: ["TodoCore"]
        ),
    ]
)