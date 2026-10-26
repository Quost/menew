// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Menew",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Menew",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Menew",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                // Sparkle.framework vai em Contents/Frameworks
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        )
    ]
)
