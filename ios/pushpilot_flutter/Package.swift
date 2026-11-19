// swift-tools-version: 5.9

import Foundation
import PackageDescription

// Local development only: the native iOS SDK is the sibling checkout `pushpilot-ios`. Flutter reaches this
// manifest through a symlink, so the path is resolved from the real file. At release replace this line and
// the `pushPilot` use below with `.package(url: "<pushpilot-ios repository URL>", from: "2.2.0")`.
let pushPilot = Package.Dependency.package(path: URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
    .deletingLastPathComponent().appendingPathComponent("../../../pushpilot-ios").standardized.path)

let package = Package(
    name: "pushpilot_flutter",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "pushpilot-flutter", targets: ["pushpilot_flutter"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        pushPilot,
    ],
    targets: [
        .target(
            name: "pushpilot_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "PushPilot", package: "pushpilot-ios"),
            ]
        )
    ]
)
