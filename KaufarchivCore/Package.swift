// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KaufarchivCore",
    defaultLocalization: "de",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KaufarchivCore", targets: ["KaufarchivCore"]),
        // Prüfwerkzeug: lässt echte Belegfotos durch Texterkennung und Parser laufen (macOS, für CI).
        .executable(name: "ReceiptEval", targets: ["ReceiptEval"])
    ],
    targets: [
        .target(name: "KaufarchivCore"),
        .executableTarget(name: "ReceiptEval", dependencies: ["KaufarchivCore"]),
        .testTarget(name: "KaufarchivCoreTests", dependencies: ["KaufarchivCore"])
    ]
)
