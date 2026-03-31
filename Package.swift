// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AnnotationOverlay",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AnnotationOverlay", targets: ["AnnotationOverlay"]),
    ],
    targets: [
        .target(name: "AnnotationOverlay"),
    ]
)
