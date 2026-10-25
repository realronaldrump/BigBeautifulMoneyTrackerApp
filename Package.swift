// swift-tools-version: 6.0
import PackageDescription

// Run the shared calculation and persistence tests on the Mac without a simulator.
let package = Package(
    name: "MoneyTrackerCore",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "MoneyTrackerCore",
            path: "Shared/Sources",
            exclude: ["Shared/ShiftActivityAttributes.swift"]
        ),
        .testTarget(
            name: "MoneyTrackerCoreTests",
            dependencies: ["MoneyTrackerCore"],
            path: "Tests/Sources"
        )
    ]
)
