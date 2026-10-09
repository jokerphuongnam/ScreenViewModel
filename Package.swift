// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenViewModel",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v10),
        .tvOS(.v17),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "ScreenViewModel", targets: ["ScreenViewModel"]),
        .executable(name: "ScreenViewModelExample", targets: ["ScreenViewModelExample"])
    ],
    targets: [
        .target(name: "ScreenViewModel"),
        .executableTarget(
            name: "ScreenViewModelExample",
            dependencies: ["ScreenViewModel"],
            path: "Examples/ScreenViewModelExample"
        ),
        .testTarget(
            name: "ScreenViewModelTests",
            dependencies: ["ScreenViewModel"],
            path: "Sources/Tests"
        )
    ]
)
