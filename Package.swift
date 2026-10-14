// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpeechSynthesizer",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        // Core: engine protocol + shared types + Apple's built-in engine. Zero
        // external dependencies.
        .library(name: "SpeechSynthesizer", targets: ["SpeechSynthesizer"]),
        // Kokoro-82M (Apache-2.0) — CoreML/ANE, mobile. FluidAudio-backed.
        .library(name: "KokoroTTS", targets: ["KokoroTTS"]),
        // PocketTTS (MIT) — CoreML, mobile, voice cloning. FluidAudio-backed.
        .library(name: "PocketTTS", targets: ["PocketTTS"]),
        // Chatterbox (MIT) + Qwen3-TTS (Apache) — MLX/GPU, Mac-class. mlx-audio-swift.
        .library(name: "MLXTTS", targets: ["MLXTTS"]),
        // Supertonic 3 (OpenRAIL-M) — ONNX Runtime, 31 languages, mobile-class.
        .library(name: "SupertonicTTS", targets: ["SupertonicTTS"]),
        // Fish Audio Drama 3 (Fish Audio Community License, NOT commercial-safe) —
        // MLX/GPU, expressive inline cues, 36 GB Macs. Opt-in: the engine refuses
        // to start until its licence version is named.
        .library(name: "DramaTTS", targets: ["DramaTTS"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.2"),
        // Pinned to a tag rather than a branch. SwiftPM refuses to let a
        // stable-versioned package depend on an unstable one, so a branch
        // requirement here makes this package impossible to release —
        // consumers cannot depend on it by version at all.
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", from: "0.1.5"),
        // 0.32: Drama 3 matches the mlx 0.32 reference layer for layer; 0.31.6 drifted from layer 0.
        .package(url: "https://github.com/ml-explore/mlx-swift.git", .upToNextMajor(from: "0.32.3")),
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager.git", from: "1.16.0"),
        // Drama 3 reuses the gated-delta kernel and switch (expert) layers.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", .upToNextMajor(from: "3.32.3")),
        .package(url: "https://github.com/huggingface/swift-transformers.git", .upToNextMajor(from: "1.1.6")),
    ],
    targets: [
        .target(
            name: "SpeechSynthesizer",
            dependencies: []
        ),
        .target(
            name: "KokoroTTS",
            dependencies: [
                "SpeechSynthesizer",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .target(
            name: "PocketTTS",
            dependencies: [
                "SpeechSynthesizer",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .target(
            name: "MLXTTS",
            dependencies: [
                "SpeechSynthesizer",
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
                .product(name: "MLX", package: "mlx-swift"),
            ]
        ),
        .target(
            name: "SupertonicTTS",
            dependencies: [
                "SpeechSynthesizer",
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
            ]
        ),
        .target(
            name: "DramaTTS",
            dependencies: [
                "SpeechSynthesizer",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXAudioCodecs", package: "mlx-audio-swift"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        ),
        .testTarget(
            name: "DramaTTSTests",
            dependencies: [
                "DramaTTS", "SpeechSynthesizer",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXAudioCodecs", package: "mlx-audio-swift"),
            ],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "KokoroTTSTests",
            dependencies: ["KokoroTTS"]
        ),
        .testTarget(
            name: "SpeechSynthesizerTests",
            dependencies: ["SpeechSynthesizer"]
        ),
    ]
)

// Swift 7's import rule, today: a file must import every module whose members
// it uses, rather than leaning on another file's imports.
for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + [.enableUpcomingFeature("MemberImportVisibility")]
}
