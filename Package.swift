// swift-tools-version: 6.3.3

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "swift-witnesses",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        .library(
            name: "Witnesses",
            targets: ["Witnesses"]
        ),
        .library(
            name: "Witnesses Macros",
            targets: ["Witnesses Macros"]
        ),
        .library(
            name: "Witnesses Test Support",
            targets: ["Witnesses Test Support"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0"..<"603.0.0"),
        .package(url: "https://github.com/swift-primitives/swift-witness-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-source-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-optic-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-finite-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-ownership-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-dependency-primitives.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Witnesses",
            dependencies: [
                "Witnesses Macros",
                .product(name: "Witness Primitives", package: "swift-witness-primitives"),
                .product(name: "Source Primitives", package: "swift-source-primitives"),
                .product(name: "Ownership Primitives", package: "swift-ownership-primitives"),
                .product(name: "Dependency Primitives", package: "swift-dependency-primitives"),
            ]
        ),
        .target(
            name: "Witnesses Macros",
            dependencies: [
                "Witnesses Macros Implementation",
                .product(name: "Witness Primitives", package: "swift-witness-primitives"),
                .product(name: "Optic Primitives", package: "swift-optic-primitives"),
                .product(name: "Finite Primitives", package: "swift-finite-primitives"),
            ]
        ),
        .macro(
            name: "Witnesses Macros Implementation",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "Witnesses Test Support",
            dependencies: [
                "Witnesses",
            ],
            path: "Tests/Support"
        ),
        .testTarget(
            name: "Witnesses Tests",
            dependencies: [
                "Witnesses"
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("LifetimeDependence"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("LifetimeDependence"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
