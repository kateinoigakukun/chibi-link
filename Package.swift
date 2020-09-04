// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "ChibiLink",
    products: [
        .executable(name: "strip-debug", targets: ["strip-debug"]),
        .executable(name: "chibi-link", targets: ["chibi-link"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "strip-debug", dependencies: []),
        .target(name: "chibi-link", dependencies: ["ChibiLink"]),
        .target(name: "ChibiLink"),
        .testTarget(name: "ChibiLinkTests", dependencies: ["ChibiLink"]),
    ]
)
