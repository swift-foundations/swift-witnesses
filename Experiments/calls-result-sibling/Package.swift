// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "calls-result-sibling",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../../../swift-primitives/swift-optic-primitives"),
        .package(path: "../../../../swift-primitives/swift-finite-primitives"),
        .package(path: "../../../../swift-primitives/swift-standard-library-extensions"),
    ],
    targets: [
        .executableTarget(
            name: "calls-result-sibling",
            dependencies: [
                .product(name: "Optic Primitives", package: "swift-optic-primitives"),
                .product(name: "Finite Primitives", package: "swift-finite-primitives"),
                .product(name: "Standard Library Extensions", package: "swift-standard-library-extensions"),
            ]
        )
    ]
)
