// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CordaMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "CordaMac",
            targets: ["CordaMac"]
        )
    ],
    targets: [
        .executableTarget(
            name: "CordaMac",
            path: "CordaMac",
            exclude: [
                "CordaMac.entitlements",
                "Info.plist"
            ]
        )
    ]
)
