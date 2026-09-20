// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacShapearator",
    platforms: [
        // The shipped app targets 15.4 (project.yml says why). This package
        // exists to build and test the sources, and swift-tools 5.9 cannot
        // express .v15 -- .v14 is enough for every API the sources use, and
        // the product's real floor is enforced by check_minimum_os.py.
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacShapearator", targets: ["MacShapearator"])
    ],
    targets: [
        .executableTarget(
            name: "MacShapearator",
            path: "Sources/MacShapearator",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "MacShapearatorTests",
            dependencies: ["MacShapearator"],
            path: "Tests/MacShapearatorTests",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        )
    ]
)
