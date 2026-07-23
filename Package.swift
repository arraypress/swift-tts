// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpeechSynthesizer",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        // Core: engine protocol + shared types. Zero external dependencies.
        .library(
            name: "SpeechSynthesizer",
            targets: ["SpeechSynthesizer"]
        ),
    ],
    targets: [
        .target(
            name: "SpeechSynthesizer",
            dependencies: []
        ),
        .testTarget(
            name: "SpeechSynthesizerTests",
            dependencies: ["SpeechSynthesizer"]
        ),
    ]
)

// MARK: - Engine backends (opt-in)
//
// The four model adapters live in `Engines/` as ready-to-wire reference code.
// Each pulls a heavy dependency, so they're opt-in — enable only what you use.
// To turn one on: add its dependency below, declare its target, and move its
// file from `Engines/` into `Sources/<Target>/`. Build on macOS 26 and verify
// the SDK signatures against your resolved version.
//
// Kokoro (CoreML/ANE, mobile) + PocketTTS (CoreML, mobile, cloning) — FluidAudio:
//   dependencies += .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.0")
//   targets += .target(name: "KokoroTTS", dependencies: [
//       "SpeechSynthesizer", .product(name: "FluidAudio", package: "FluidAudio")])
//   targets += .target(name: "PocketTTS", dependencies: [
//       "SpeechSynthesizer", .product(name: "FluidAudio", package: "FluidAudio")])
//
// Chatterbox (MLX/GPU, Mac) + Qwen3-TTS (MLX/GPU, Mac) — mlx-audio-swift:
//   dependencies += .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", from: "1.0.0")
//   targets += .target(name: "ChatterboxTTS", dependencies: [
//       "SpeechSynthesizer", .product(name: "MLXAudioTTS", package: "mlx-audio-swift")])
//   targets += .target(name: "Qwen3TTS", dependencies: [
//       "SpeechSynthesizer", .product(name: "MLXAudioTTS", package: "mlx-audio-swift")])
