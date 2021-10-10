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
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "0.4.0")),
        .package(url: "https://github.com/typelift/SwiftCheck.git", from: "0.12.0")
    ],
    targets: [
        .target(name: "Wlroots"),
        .target(name: "Libawc", dependencies: ["awc_config", "Wlroots"]),
        .systemLibrary(name: "awc_config"),
        .target(
            name: "awc",
            dependencies: [
                "awc_config", 
                "Libawc", 
                "Wlroots",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),
        .testTarget(
            name: "awcTests",
            dependencies: ["awc"],
            resources: [
                .copy("Fixtures")
            ]),
        .testTarget(
            name: "awcConfigTests",
            dependencies: ["awc_config", "Libawc", "SwiftCheck"],
            resources: [
                .copy("Fixtures")
            ]),
        .testTarget(name: "testHelpers", dependencies: ["awc_config"]),
    ]
)
