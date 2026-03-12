// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "borrowing-observation-experiment",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "BorrowingObservation",
            path: "Sources",
            swiftSettings: [
                .enableExperimentalFeature("Lifetimes"),
            ]
        ),
    ]
)
