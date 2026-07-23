# Swift TTS (SpeechSynthesizer)

On-device, **commercial-safe** text-to-speech for macOS and iOS. One engine protocol, four curated open models — the text-to-speech counterpart to a multi-engine transcriber, where every backend returns the same `SpokenAudio` regardless of which model produced it.

Models are **downloaded on first use** and cached, so the app ships small and every later run is fully offline.

## The models

All four are curated to be **commercial-safe** (Apache-2.0 / MIT *weights*) and split by runtime tier:

| Model | License | Runtime | Runs on iPhone? | Cloning | Best for |
|---|---|---|---|---|---|
| **Kokoro-82M** | Apache-2.0 | CoreML / ANE | ✅ | — | the fast, light default (9 langs, SSML) |
| **PocketTTS** | MIT | CoreML | ✅ | ✅ | small + streaming + voice cloning on mobile |
| **Chatterbox** | MIT | MLX / GPU | ❌ Mac | ✅ | best-sounding, emotion + 10s cloning |
| **Qwen3-TTS** | Apache-2.0 | MLX / GPU | ❌ Mac | ✅ | multilingual, long-form |

> **License hygiene:** only Apache/MIT-*weights* models are included. Restrictive models (Fish S2, F5-TTS, Higgs, XTTS) and Llama-licensed weights (Orpheus) are deliberately **not** supported.

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

## Enabling an engine (opt-in)

The engine adapters live in `Engines/` as ready-to-wire reference code, kept out of the compiled build so the core has zero dependencies. Turn on only what you use:

1. Add the dependency in `Package.swift` (templates are in the commented block there).
2. Declare the target, e.g. for Kokoro:
   ```swift
   .target(name: "KokoroTTS", dependencies: [
       "SpeechSynthesizer", .product(name: "FluidAudio", package: "FluidAudio")])
   ```
3. Move `Engines/KokoroEngine.swift` → `Sources/KokoroTTS/`.
4. Build on macOS 26 and verify the SDK signatures against your resolved version.

```swift
import KokoroTTS

let engine = KokoroEngine()
try await engine.prepare()
let audio = try await engine.synthesize("Hello from Kokoro.")
```

## Status

- ✅ **Core (`SpeechSynthesizer`) is built and unit-tested** — `SpokenAudio` WAV encoding, `TTSModel` metadata/licensing, `SynthesisOptions`, errors. Zero deps, runs anywhere.
- 🔌 **Engine adapters are ready-to-wire reference implementations** written against FluidAudio's and mlx-audio-swift's documented APIs. They pull heavy SDKs and require on-device (ANE/GPU) model runs, so **verify signatures + confirm audio generation on a real device** when you enable one. The exact SDK type/method names are flagged inline in each `Engines/*.swift` file.

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
