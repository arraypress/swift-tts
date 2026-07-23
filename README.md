# Swift TTS (SpeechSynthesizer)

On-device, **commercial-safe** text-to-speech for macOS and iOS. One engine protocol, four curated open models — the text-to-speech counterpart to a multi-engine transcriber, where every backend returns the same `SpokenAudio` regardless of which model produced it.

Models are **downloaded on first use** and cached, so the app ships small and every later run is fully offline.

## The models

All are commercial-safe (Apple's system voices, or Apache-2.0 / MIT *weights*) and split by runtime tier:

| Model | License | Runtime | Runs on iPhone? | Cloning | Status | Best for |
|---|---|---|---|---|---|---|
| **Apple (system)** | Apple (free to use) | System | ✅ | — | ✅ built-in | zero-config default & fallback, every device |
| **Kokoro-82M** | Apache-2.0 | CoreML / ANE | ✅ | — | ✅ compiled target | fast, light (9 langs, SSML) |
| **PocketTTS** | MIT | CoreML | ✅ | ✅ | ✅ compiled target | small + cloning on mobile |
| **Chatterbox** | MIT | MLX / GPU | ❌ Mac | ✅ | 🔌 reference | best-sounding, emotion + 10s cloning |
| **Qwen3-TTS** | Apache-2.0 | MLX / GPU | ❌ Mac | ✅ | 🔌 reference | multilingual, long-form |

> **License hygiene:** only Apple's system voices and Apache/MIT-*weights* models are included. Restrictive models (Fish S2, F5-TTS, Higgs, XTTS) and Llama-licensed weights (Orpheus) are deliberately **not** supported.

## Architecture

- **`SpeechSynthesizer`** (this package) — the core: the `TTSEngine` protocol, the shared `SpokenAudio` output type (WAV + `AVAudioPCMBuffer`), `TTSModel` metadata, `TTSVoice`, `SynthesisOptions`, `TTSError`. **Zero external dependencies.**
- **Engine backends** — one adapter per model, each wrapping a real SDK:
  - Kokoro + PocketTTS → **[FluidAudio](https://github.com/FluidInference/FluidAudio)** (CoreML/ANE)
  - Chatterbox + Qwen3 → **[mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift)** (MLX/GPU)

Program against `TTSEngine` and the models are interchangeable.

```swift
import SpeechSynthesizer

func speak(_ text: String, with engine: some TTSEngine) async throws -> SpokenAudio {
    try await engine.prepare { progress in print("downloading model… \(Int(progress * 100))%") }
    let audio = try await engine.synthesize(text)   // SpokenAudio (24 kHz mono)
    try audio.write(toWAV: URL(fileURLWithPath: "/tmp/out.wav"))
    return audio
}
```

## Using the engines

**Apple** (zero setup, in the core):
```swift
import SpeechSynthesizer
let engine = AppleEngine()
let audio = try await engine.synthesize("Hello.")
```

**Kokoro / PocketTTS** (real products — just add this package and import):
```swift
import KokoroTTS   // or PocketTTS

let engine = KokoroEngine()
try await engine.prepare { print("downloading… \(Int($0 * 100))%") }  // ~350 MB first run
let audio = try await engine.synthesize("Hello from Kokoro.")
```

**Chatterbox / Qwen3** (MLX, Mac-class) live in `Engines/` as reference adapters. To enable one: add mlx-audio-swift (templates are in the commented block in `Package.swift`), declare its target, move its file from `Engines/` into `Sources/`, and verify the SDK signatures.

## Status

- ✅ **Core (`SpeechSynthesizer`) — built + unit-tested (19 tests).** `SpokenAudio` WAV encode/decode, `TTSModel` metadata/licensing, `SynthesisOptions`, errors. Zero deps.
- ✅ **AppleEngine — real, compiled, in the core.** Uses `AVSpeechSynthesizer`; no download, every device. (Its live render needs an app run loop, so it's guard-tested here and runs in-app.)
- ✅ **KokoroTTS + PocketTTS — real, compiled targets** against **FluidAudio 0.15.2** (verified: correct actor API, WAV decode, `swift build` clean). First-run **synthesis downloads the model (~350 MB) from Hugging Face then runs on the ANE — confirm that live run on your machine** (the compile + wiring is done).
- 🔌 **ChatterboxTTS + Qwen3-TTS — reference adapters in `Engines/`** against mlx-audio-swift's documented API. Enable + verify when you want the MLX/GPU (Mac-class) models.

## How model downloading works

The app bundles only *code*, never weights. On the first `prepare()` for a model, its weights download (from Hugging Face by default via the backing SDK) and cache to disk; every later run loads locally and is fully offline. A user who only uses Kokoro never downloads Chatterbox's gigabytes.

For a shipping commercial product, consider hosting the weights yourself (your own CDN) rather than depending on Hugging Face availability.

## Testing

```bash
swift test
```

Covers the core: WAV encoding (header, sample rate, clamping), model licensing/runtime invariants, options clamping, and errors.

## Requirements

- macOS 14+ / iOS 17+ (the core). Individual engines raise this — FluidAudio and MLX target newer OSes; a Core AI backend (WWDC 2026) would require macOS 27 / iOS 27.
- Swift 6.0+

## License

MIT License (this package) — see LICENSE. Each **model's** weights carry their own license (all Apache/MIT); see the table above.

## Author

Created by David Sherlock ([ArrayPress](https://github.com/arraypress)) in 2026.
