// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sovereign",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SovereignMac", targets: ["SovereignMac"]),
    ],
    targets: [
        .executableTarget(
            name: "SovereignMac",
            dependencies: [],
            path: "Sources/SovereignMac",
            exclude: ["Info.plist", "SovereignMac.entitlements"]
        ),
        .testTarget(
            name: "SovereignMacTests",
            dependencies: ["SovereignMac"],
            path: "Tests/SovereignMacTests"
        ),
    ]
)
