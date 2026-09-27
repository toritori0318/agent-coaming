// swift-tools-version: 6.0
import PackageDescription

// COAMING_CURSOR=1 compiles the optional Cursor path. The default build omits it. See ProviderID.included.
let cursorSettings: [SwiftSetting] = Context.environment["COAMING_CURSOR"] == "1" ? [.define("COAMING_CURSOR")] : []

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
            swiftSettings: cursorSettings,
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "coaming",
            dependencies: ["CoamingCore"],
            swiftSettings: cursorSettings
        ),
        .testTarget(
            name: "CoamingCoreTests",
            dependencies: ["CoamingCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: cursorSettings
        ),
    ]
)
