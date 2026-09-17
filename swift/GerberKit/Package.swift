// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GerberKit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "GerberKit", targets: ["GerberKit"])
    ],
    targets: [
        .target(
            name: "GerberKit",
            resources: [.process("Resources")],
            linkerSettings: [.linkedLibrary("z")]
        ),
        .testTarget(name: "GerberKitTests", dependencies: ["GerberKit"], resources: [.copy("Fixtures")])
    ]
)
