// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "awc",
    products: [
        .executable(name: "awc", targets: ["awc"]),
        .executable(name: "NeonSlurp", targets: ["NeonSlurp"]),
        .executable(name: "OutputHud", targets: ["OutputHud"]),
        .library(name: "Libawc", targets: ["Libawc"]),
        .library(name: "Wlroots", type: .dynamic, targets: ["Wlroots"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "1.0.0")),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/typelift/SwiftCheck.git", from: "0.12.0")
    ],
    targets: [
        .target(name: "Cairo", dependencies: ["CCairo"]),
        .target(name: "ControlProtocol"),
        .target(name: "DataStructures"),
        .target(name: "Wlroots"),
        .target(
            name: "Libawc",
            dependencies: [
                "awc_config",
                "DataStructures",
                "Wlroots"
            ]
        ),
        .target(
            name: "LogHandlers",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .systemLibrary(name: "awc_config"),
        .systemLibrary(name: "CCairo", pkgConfig: "cairo"),
        .systemLibrary(name: "CEpoll"),
        .systemLibrary(name: "CWaylandEgl"),
        .systemLibrary(name: "CXkbCommon", pkgConfig: "xkbcommon"),
        .systemLibrary(name: "Drm"),
        .systemLibrary(name: "EGlext"),
        .systemLibrary(name: "Gles2ext"),
        .systemLibrary(name: "Gles32"),
        .systemLibrary(name: "LayerShellClient"),
        .target(
            name: "awc",
            dependencies: [
                "awc_config",
                "ControlProtocol",
                "Libawc",
                "LogHandlers",
                "Wlroots",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log")
            ]),
        .target(
            name: "ClientCommons",
            dependencies: [
                "CWaylandEgl",
                "EGlext",
                "Gles2ext",
                "LayerShellClient",
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .target(
            name: "LayoutVisualizer",
            dependencies: [
                "CCairo",
                "Libawc",
            ]
        ),
        .target(
            name: "NeonRenderer",
            dependencies: [
                "Cairo",
                "EGlext",
                "Gles2ext",
                "Gles32",
                .product(name: "Logging", package: "swift-log"),      
            ]
        ),
        .target(
            name: "NeonSlurp",
            dependencies: [
                "ClientCommons",
                "CXkbCommon",
                "DataStructures",
                "LogHandlers",
                "NeonRenderer",
                .product(name: "Logging", package: "swift-log"),      
            ]
        ),
        .target(
            name: "OutputHud",
            dependencies: [
                "Cairo",
                "CEpoll",
                "ClientCommons",
                "ControlProtocol",
                "DataStructures",
                "EGlext",
                "Gles2ext",
                "LayerShellClient",
                "LogHandlers",
                "NeonRenderer",
                .product(name: "Logging", package: "swift-log"),
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
