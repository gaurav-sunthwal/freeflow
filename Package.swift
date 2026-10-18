// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "FreeFlow",
    platforms: [.macOS(.v26)],
    targets: [
        // Prebuilt whisper.cpp (MIT, ggml-org/whisper.cpp) with Metal acceleration, pinned by checksum.
        .binaryTarget(
            name: "whisper",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-b5454-xcframework.zip",
            checksum: "e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b"
        ),
        .executableTarget(
            name: "FreeFlow",
            dependencies: ["whisper"],
            path: "Sources/FreeFlow",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("FoundationModels"),
                .linkedFramework("ApplicationServices"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        )
    ]
)
