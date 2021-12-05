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
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "1.0.0")),
        .package(url: "https://github.com/typelift/SwiftCheck.git", from: "0.12.0")
    ],
    targets: [
        .target(name: "Wlroots"),
        .target(name: "Libawc", dependencies: ["awc_config", "Wlroots"]),
        .systemLibrary(name: "awc_config"),
        .systemLibrary(name: "Cairo"),
        .systemLibrary(name: "Drm"),
        .systemLibrary(name: "Gles2ext"),
        .systemLibrary(name: "Gles32"),
        .target(
            name: "awc",
            dependencies: [
                "awc_config",
                "Cairo",
                "Drm",
                "Gles2ext",
                "Gles32",
                "Libawc",
                "Wlroots",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),
        .target(
            name: "LayoutVisualizer",
            dependencies: [
                "Cairo",
                "Libawc",
            ]
        ),
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
