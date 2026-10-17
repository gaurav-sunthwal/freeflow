// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "FreeFlow",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "FreeFlow",
            path: "Sources/FreeFlow",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("FoundationModels"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)
