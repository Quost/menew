// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MeuMenu",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MeuMenu",
            path: "Sources/MeuMenu",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
