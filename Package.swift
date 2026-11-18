// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StayAwake",
    products: [
        .library(name: "StayAwakeCore", targets: ["StayAwakeCore"]),
    ],
    targets: [
        .target(name: "StayAwakeCore"),
        .testTarget(name: "StayAwakeCoreTests", dependencies: ["StayAwakeCore"]),
    ]
)
