// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "ChibiLink",
    products: [
        .executable(name: "chibi-link", targets: ["chibi-link"]),
        .library(name: "ChibiLink", targets: ["ChibiLink"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "chibi-link", dependencies: ["ChibiLink"]),
        .target(name: "ChibiLink"),
        .testTarget(name: "ChibiLinkTests", dependencies: ["ChibiLink"]),
    ]
)
