// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AgentShade",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AgentShadeCore", targets: ["AgentShadeCore"]),
        .executable(name: "AgentShade", targets: ["AgentShade"]),
        .executable(name: "AgentShadeCoreChecks", targets: ["AgentShadeCoreChecks"])
    ],
    targets: [
        .target(name: "AgentShadeCore"),
        .executableTarget(name: "AgentShade", dependencies: ["AgentShadeCore"]),
        .executableTarget(
            name: "AgentShadeCoreChecks",
            dependencies: ["AgentShadeCore"],
            path: "Checks/AgentShadeCoreChecks"
        )
    ],
    swiftLanguageVersions: [.v5]
)
