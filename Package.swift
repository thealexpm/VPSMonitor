// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VPSMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VPSMonitor", targets: ["VPSMonitor"]),
        .executable(name: "VPSMonitorProbe", targets: ["VPSMonitorProbe"])
    ],
    targets: [
        .target(name: "VPSMonitorCore"),
        .executableTarget(
            name: "VPSMonitor",
            dependencies: ["VPSMonitorCore"]
        ),
        .executableTarget(
            name: "VPSMonitorProbe",
            dependencies: ["VPSMonitorCore"]
        ),
        .testTarget(
            name: "VPSMonitorCoreTests",
            dependencies: ["VPSMonitorCore"]
        )
    ]
)
