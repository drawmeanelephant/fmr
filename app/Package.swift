// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FmrApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FmrApp", targets: ["FmrApp"])
    ],
    targets: [
        .executableTarget(
            name: "FmrApp",
            path: "Sources/FmrApp"
        ),
        .testTarget(
            name: "FmrAppTests",
            dependencies: ["FmrApp"],
            path: "Tests/FmrAppTests"
        )
    ]
)
