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
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.2"),
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
        .testTarget(
            name: "SpeechSynthesizerTests",
            dependencies: ["SpeechSynthesizer"]
        ),
    ]
)

// MARK: - MLX engine backends (opt-in, Mac-class)
//
// Chatterbox (MIT, best-sounding) and Qwen3-TTS (Apache, multilingual) run on
// MLX/GPU. Their adapters live in `Engines/` as ready-to-wire reference code
// against mlx-audio-swift. To enable one: add the dependency, declare its
// target, and move its file into `Sources/<Target>/`.
//
//   dependencies += .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", from: "1.0.0")
//   targets += .target(name: "ChatterboxTTS", dependencies: [
//       "SpeechSynthesizer", .product(name: "MLXAudioTTS", package: "mlx-audio-swift")])
//   targets += .target(name: "Qwen3TTS", dependencies: [
//       "SpeechSynthesizer", .product(name: "MLXAudioTTS", package: "mlx-audio-swift")])