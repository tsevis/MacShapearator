// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacShapearator",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacShapearator", targets: ["MacShapearator"])
    ],
    targets: [
        .executableTarget(
            name: "MacShapearator",
            path: "Sources/MacShapearator"
        ),
        .testTarget(
            name: "MacShapearatorTests",
            dependencies: ["MacShapearator"],
            path: "Tests/MacShapearatorTests"
        )
    ]
)
