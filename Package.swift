// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "awc",
    products: [
        .executable(name: "awc", targets: ["awc"]),
        .library(name: "Libawc", targets: ["Libawc"]),
        .library(name: "Wlroots", type: .dynamic, targets: ["Wlroots"]),
    ],
    targets: [
        .target(name: "Wlroots"),
        .target(name: "Libawc", dependencies: ["awc_config", "Wlroots"]),
        .systemLibrary(name: "awc_config"),
        .target(
            name: "awc",
            dependencies: ["awc_config", "Libawc", "Wlroots"]),
        .testTarget(
            name: "awcTests",
            dependencies: ["awc"],
            resources: [
                .copy("Fixtures")
            ]),
        .testTarget(
            name: "awcConfigTests",
            dependencies: ["awc_config", "Libawc"],
            resources: [
                .copy("Fixtures")
            ]),
        .testTarget(name: "testHelpers", dependencies: ["awc_config"]),
    ]
)
