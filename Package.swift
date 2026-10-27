// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftTransGUI",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        .target(
            name: "TransGUICore"
        ),
        .executableTarget(
            name: "SwiftTransGUI",
            dependencies: ["TransGUICore"],
            path: "Sources/SwiftTransGUI"
        ),
        .executableTarget(
            name: "rpc-selftest",
            dependencies: ["TransGUICore"],
            path: "Sources/rpc-selftest"
        ),
        .testTarget(
            name: "TransGUICoreTests",
            dependencies: ["TransGUICore"]
        ),
        .testTarget(
            name: "SwiftTransGUITests",
            dependencies: ["SwiftTransGUI"]
        ),
    ]
)
