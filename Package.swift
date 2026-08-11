// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RobloxReplay",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "roblox-replay", targets: ["RobloxReplay"])
    ],
    targets: [
        .executableTarget(name: "RobloxReplay")
    ]
)
