// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lingo",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Lingo",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Lingo",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("Translation"),
                .linkedFramework("NaturalLanguage"),
            ]
        )
    ]
)
