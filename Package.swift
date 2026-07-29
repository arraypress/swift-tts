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
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.2"),
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", .upToNextMajor(from: "0.30.6")),
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager.git", from: "1.16.0"),
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
        .testTarget(
            name: "SpeechSynthesizerTests",
            dependencies: ["SpeechSynthesizer"]
        ),
    ]
)
