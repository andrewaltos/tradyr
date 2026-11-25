// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tradyr",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Tradyr", targets: ["Tradyr"]),
        .library(name: "TradyrCore", targets: ["TradyrCore"]),
    ],
    targets: [
        .target(name: "TradyrCore"),
        .executableTarget(name: "Tradyr", dependencies: ["TradyrCore"]),
        .executableTarget(name: "tradyr-probe", dependencies: ["TradyrCore"]),
        .testTarget(name: "TradyrCoreTests", dependencies: ["TradyrCore"]),
    ],
    swiftLanguageModes: [.v5]
)
