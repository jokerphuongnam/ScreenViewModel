// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenViewModel",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "ScreenViewModel", targets: ["ScreenViewModel"])
    ],
    targets: [
        .target(name: "ScreenViewModel")
    ]
)
