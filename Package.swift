// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "iData",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "iDataCore", targets: ["iDataCore"]),
        .executable(name: "iData", targets: ["iData"]),
    ],
    targets: [
        .target(
            name: "iDataCore"
        ),
        .executableTarget(
            name: "iData",
            dependencies: ["iDataCore"]
        ),
        .testTarget(
            name: "iDataCoreTests",
            dependencies: ["iDataCore"]
        ),
        .testTarget(
            name: "iDataAppTests",
            dependencies: ["iData", "iDataCore"]
        ),
    ]
)
