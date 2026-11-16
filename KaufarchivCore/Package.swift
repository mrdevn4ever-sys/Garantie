// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KaufarchivCore",
    defaultLocalization: "de",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KaufarchivCore", targets: ["KaufarchivCore"])
    ],
    targets: [
        .target(name: "KaufarchivCore"),
        .testTarget(name: "KaufarchivCoreTests", dependencies: ["KaufarchivCore"])
    ]
)
