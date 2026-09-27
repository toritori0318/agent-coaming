// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoamingCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CoamingCore", targets: ["CoamingCore"]),
        .executable(name: "coaming", targets: ["coaming"]),
    ],
    targets: [
        .target(
            name: "CoamingCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "coaming",
            dependencies: ["CoamingCore"]
        ),
        .testTarget(
            name: "CoamingCoreTests",
            dependencies: ["CoamingCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
