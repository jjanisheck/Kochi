// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KochiApp",
    platforms: [
        .macOS(.v14)  // Apple Foundation Models / Speech; macOS-only app
    ],
    products: [
        .library(
            name: "KochiApp",
            targets: ["KochiApp"])
    ],
    dependencies: [
        // ✅ Using 100% Apple Native Frameworks:
        // - Speech framework (SFSpeechRecognizer) for transcription
        // - NaturalLanguage framework (NLEmbedding) for semantic AI
        // - No external dependencies needed!
    ],
    targets: [
        .target(
            name: "KochiApp",
            dependencies: []  // No external dependencies - 100% Apple native!
        )
    ]
)