// swift-tools-version: 6.2

// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-witnesses open source project
//
// Copyright (c) 2024-2025 Coen ten Thije Boonkkamp and the swift-witnesses
// project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

import PackageDescription

let package = Package(
    name: "swift-witnesses-tests",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26),
    ],
    dependencies: [
        .package(path: ".."),
        .package(path: "../../swift-testing"),
    ],
    targets: [
        .testTarget(
            name: "Witnesses Tests",
            dependencies: [
                .product(name: "Witnesses", package: "swift-witnesses"),
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Witnesses Tests"
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
