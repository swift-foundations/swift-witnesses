// swift-tools-version: 6.2

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "swift-witnessess",
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
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
        .package(path: "../../swift-primitives/swift-witness-primitives"),
    ],
    targets: [
        .target(
            name: "Witnesses",
            dependencies: [
                "Witnesses Macros",
                .product(name: "Witness Macros", package: "swift-witness-primitives"),
            ]
        ),
        .target(
            name: "Witnesses Macros",
            dependencies: [
                "Witnesses Macros Implementation",
                .product(name: "Witness Primitives", package: "swift-witness-primitives"),
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
        .testTarget(
            name: "Witnesses Tests",
            dependencies: [
                "Witnesses",
            ],
            path: "Tests/Witnesses Tests"
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let settings: [SwiftSetting] = [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .strictMemorySafety(),
    ]
    target.swiftSettings = (target.swiftSettings ?? []) + settings
}
