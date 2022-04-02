// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "ChibiLink",
    products: [
        .executable(name: "chibi-link", targets: ["chibi-link"]),
        .library(name: "ChibiLink", targets: ["ChibiLink"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "chibi-link",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "ChibiLink",
            ]),
        .target(name: "ChibiLink"),
        .testTarget(name: "ChibiLinkTests", dependencies: ["ChibiLink"]),
    ]
)
