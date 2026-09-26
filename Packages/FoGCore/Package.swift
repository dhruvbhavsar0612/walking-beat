// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FoGCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "FoGCore", targets: ["FoGCore"]),
        .library(name: "FoGKit", targets: ["FoGKit"]),
    ],
    targets: [
        .target(name: "FoGCore", resources: [.copy("Resources/detector_profiles.json")]),
        .target(name: "FoGKit", dependencies: ["FoGCore"]),
        .testTarget(name: "FoGCoreTests", dependencies: ["FoGCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "FoGKitTests", dependencies: ["FoGKit"]),
    ]
)
