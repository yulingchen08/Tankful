// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tankful",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TankfulCore", targets: ["TankfulCore"]),
        .executable(name: "TankfulApp", targets: ["TankfulApp"]),
        .executable(name: "TankfulBridge", targets: ["TankfulBridge"])
    ],
    targets: [
        .target(
            name: "TankfulCore",
            path: "Sources/TankfulCore"
        ),
        .executableTarget(
            name: "TankfulApp",
            dependencies: ["TankfulCore"],
            path: "Sources/TankfulApp",
            // Info.plist and AppIcon.png are consumed by Scripts/build-app.sh when
            // assembling the bundle, not by SwiftPM.
            exclude: ["Resources/Info.plist", "Resources/AppIcon.png"],
            resources: [.copy("Resources/PanelIcon.png")]
        ),
        .executableTarget(
            name: "TankfulBridge",
            dependencies: ["TankfulCore"],
            path: "Sources/TankfulBridge"
        ),
        .testTarget(
            name: "TankfulCoreTests",
            dependencies: ["TankfulCore"],
            path: "Tests/TankfulCoreTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
