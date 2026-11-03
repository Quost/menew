// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Menew",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Modelo e desenhos dos widgets, usados pelo app (escreve e tira as capturas) e pela extensão
        .target(name: "MenewShared", path: "Sources/MenewShared",
                swiftSettings: [.unsafeFlags(["-application-extension"])]),
        // A extensão de widgets (vai em Menew.app/Contents/PlugIns/MenewWidgets.appex)
        .executableTarget(
            name: "MenewWidgets",
            dependencies: ["MenewShared"],
            path: "Sources/MenewWidgets",
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [
                .linkedFramework("WidgetKit"),
                .unsafeFlags(["-Xlinker", "-application_extension"]),
            ]
        ),
        .executableTarget(
            name: "Menew",
            dependencies: [.product(name: "Sparkle", package: "Sparkle"), "MenewShared"],
            path: "Sources/Menew",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("WidgetKit"),
                // Sparkle.framework vai em Contents/Frameworks
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        // Lógica pura do app (senhas, bateria, reuniões, atas, busca): `swift test`, e em todo pull request
        .testTarget(name: "MenewTests", dependencies: ["Menew"], path: "Tests/MenewTests"),
    ]
)
