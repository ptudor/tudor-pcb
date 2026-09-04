// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GerberKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "GerberKit", targets: ["GerberKit"])
    ],
    targets: [
        .target(name: "GerberKit"),
        .testTarget(name: "GerberKitTests", dependencies: ["GerberKit"])
    ]
)

