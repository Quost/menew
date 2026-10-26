// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Menew",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Menew",
            path: "Sources/Menew",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
