// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "awc",
    products: [
        .executable(name: "awc", targets: ["awc"]),
        .library(name: "Wlroots", type: .dynamic, targets: ["Wlroots"]),
    ],
    targets: [
        .target(name: "Wlroots"),
        .target(
            name: "awc",
            dependencies: ["Wlroots"]),
        .testTarget(
            name: "awcTests",
            dependencies: ["awc"]),
    ]
)
