// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BojiCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BojiDomain", targets: ["BojiDomain"]),
        .library(name: "BojiPersistence", targets: ["BojiPersistence"]),
        .library(name: "BojiEstimation", targets: ["BojiEstimation"]),
        .library(name: "BojiPortability", targets: ["BojiPortability"])
    ],
    targets: [
        .target(name: "BojiDomain"),
        .target(name: "BojiPersistence", dependencies: ["BojiDomain"]),
        .target(name: "BojiEstimation", dependencies: ["BojiDomain", "BojiPersistence"]),
        .target(name: "BojiPortability", dependencies: ["BojiDomain", "BojiPersistence"]),
        .testTarget(name: "BojiCoreTests", dependencies: ["BojiDomain", "BojiPersistence", "BojiEstimation", "BojiPortability"])
    ]
)
