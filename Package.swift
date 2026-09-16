// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentMeter",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AgentMeter", targets: ["AgentMeter"]),
        .executable(name: "ParserProbe", targets: ["ParserProbe"]),
    ],
    targets: [
        .target(
            name: "AgentMeterCore",
            path: "Sources/AgentMeterCore",
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "AgentMeter",
            dependencies: ["AgentMeterCore"],
            path: "Sources/AgentMeter",
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "ParserProbe",
            dependencies: ["AgentMeterCore"],
            path: "Sources/ParserProbe"
        ),
    ]
)
