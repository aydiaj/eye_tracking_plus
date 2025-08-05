// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "eye_tracking",
    platforms: [
        .iOS(.v12)
    ],
    products: [
        .library(name: "eye-tracking", targets: ["eye_tracking"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "eye_tracking",
            dependencies: [],
            resources: [
                .process("Assets")
            ]
        )
    ]
)