// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SecureScreen",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SecureScreen",
            path: "Sources/SecureScreen",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("LocalAuthentication"),
            ]
        ),
    ]
)
