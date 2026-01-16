// swift-tools-version: 6.2

import PackageDescription

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
    ],
    dependencies: [
        .package(path: "../../swift-primitives/swift-witness-primitives"),
    ],
    targets: [
        .target(
            name: "Witnesses",
            dependencies: [
                .product(name: "Witness Macros", package: "swift-witness-primitives"),
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
