// swift-tools-version: 5.9

import Foundation
import PackageDescription

// For local development against a pushpilot-ios checkout, see README -> Local development.
let pushPilot = Package.Dependency.package(url: "https://github.com/pushpilotai/pushpilot-ios", from: "2.4.0")

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
