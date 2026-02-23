// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Orbiter",
    platforms: [
        .macOS("14.0")
    ],
    products: [
        .executable(name: "Orbiter", targets: ["Orbiter"])
    ],
    targets: [
        .executableTarget(
            name: "Orbiter",
            path: "Sources/Orbiter",
            exclude: ["Orbiter.entitlements"],
            resources: [
                .process("Assets.xcassets"),
                .copy("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
