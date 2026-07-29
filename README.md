# Swift TTS (SpeechSynthesizer)

On-device, **commercial-safe** text-to-speech for macOS and iOS. One engine protocol, four curated open models — the text-to-speech counterpart to a multi-engine transcriber, where every backend returns the same `SpokenAudio` regardless of which model produced it.

Models are **downloaded on first use** and cached, so the app ships small and every later run is fully offline.

## The models

All are commercial-safe (Apple's system voices, or Apache-2.0 / MIT *weights*) and split by runtime tier:

| Model | License | Runtime | Runs on iPhone? | Cloning | Status | Best for |
|---|---|---|---|---|---|---|
| **Apple (system)** | Apple (free to use) | System | ✅ | — | ✅ built-in | zero-config default & fallback, every device |
| **Kokoro-82M** | Apache-2.0 | CoreML / ANE | ✅ | — | ✅ **verified** (live audio) | fast, light (9 langs, SSML) |
| **PocketTTS** | MIT | CoreML | ✅ | ✅ | ✅ compiled | small + cloning on mobile |
| **Chatterbox** | MIT | MLX / GPU | ❌ Mac | ✅ | ✅ compiled | best-sounding, emotion + 10s cloning |
| **Qwen3-TTS** | Apache-2.0 | MLX / GPU | ❌ Mac | ✅ | ✅ compiled | multilingual, long-form |
| **Supertonic 3** | ⚠️ OpenRAIL-M | ONNX Runtime | ✅ | — | ✅ **verified** (live audio) | 31 languages on mobile, 11x real time |

> **License hygiene:** only Apple's system voices and Apache/MIT-*weights* models are included. Restrictive models (Fish S2, F5-TTS, Higgs, XTTS) and Llama-licensed weights (Orpheus) are deliberately **not** supported.

## Architecture

- **`SpeechSynthesizer`** (this package) — the core: the `TTSEngine` protocol, the shared `SpokenAudio` output type (WAV + `AVAudioPCMBuffer`), `TTSModel` metadata, `TTSVoice`, `SynthesisOptions`, `TTSError`. **Zero external dependencies.**
- **Engine backends** — one adapter per model, each wrapping a real SDK:
  - Kokoro + PocketTTS → **[FluidAudio](https://github.com/FluidInference/FluidAudio)** (CoreML/ANE)
  - Chatterbox + Qwen3 → **[mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift)** (MLX/GPU)
  - Supertonic → **[ONNX Runtime](https://github.com/microsoft/onnxruntime-swift-package-manager)** (CPU)

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

**Supertonic** (ONNX, 31 languages, mobile-class) — `import SupertonicTTS`:
```swift
import SupertonicTTS

let engine = SupertonicEngine()             // downloads ~382 MB on first prepare()
print(engine.pendingDownloadBytes)          // 0 once cached — ask before spending it
try await engine.prepare { print($0) }
let voices = try await engine.availableVoices()   // F1–F5, M1–M5
var options = SynthesisOptions()
options.voice = voices.first { $0.id == "M3" }
let audio = try await engine.synthesize("Hello from Supertonic.", options: options)
```

**Chatterbox / Qwen3** (MLX, Mac-class) — `import MLXTTS`:
```swift
import MLXTTS

let engine = MLXEngine.chatterbox()   // or .qwen3()
try await engine.prepare()            // downloads MLX weights (GB) on first run
let audio = try await engine.synthesize("The best-sounding open model.")
```

## Status

- ✅ **Core (`SpeechSynthesizer`) — built + unit-tested (19 tests).** `SpokenAudio` WAV encode/decode, `TTSModel` metadata/licensing, `SynthesisOptions`, errors. Zero deps.
- ✅ **AppleEngine — real, compiled, in the core.** `AVSpeechSynthesizer`; no download, every device. (Live render needs an app run loop, so guard-tested here.)
- ✅ **KokoroTTS — verified end-to-end** (downloads + produces 24 kHz audio). ⚠️ **Pronunciation caveat:** FluidAudio 0.15.2's Kokoro uses a small *neural* G2P (not Kokoro's reference Misaki G2P) and mispronounces some words ("Hello" → "Hi hoy"). The audio path is correct (verified byte-identical to FluidAudio's raw output); the garbling is upstream in FluidAudio's G2P. Prefer PocketTTS for the CoreML tier until FluidAudio's Kokoro G2P improves.
- ✅ **PocketTTS — verified, sounds correct.** FluidAudio 0.15.2; the recommended CoreML/mobile engine (MIT, cloning). Runs the same pipeline as Kokoro and sounds right.
- ✅ **SupertonicTTS — verified end-to-end.** Cold install (382 MB) → 44.1 kHz audio, and the
  output was transcribed back with Apple's speech recogniser to confirm it is intelligible
  speech rather than plausible noise. 10 voices, verified to produce genuinely different audio.
  French, Spanish and Korean all synthesise (Korean exercises the NFKD path the tokenizer needs).
  **~11x real time** on an M3 Max; second run prepares in 0.30 s from cache.
- ✅ **MLXTTS (Chatterbox + Qwen3) — compiled + model download verified** against **mlx-audio-swift** (MLX/GPU). One `MLXEngine` with `.chatterbox()` / `.qwen3()` over their shared `SpeechGenerationModel`. A live run downloaded Chatterbox (416 MB) and loaded it; **GPU inference needs an Xcode app build** (MLX-Swift's Metal library doesn't bundle in a bare `swift run` CLI — a known MLX-Swift limitation, works in-app).

## Two things worth knowing about Supertonic

**Its licence is not like the others.** The weights are **OpenRAIL-M**, not Apache/MIT — commercial
use is permitted but carries use-based restrictions the other models do not impose. `TTSModel`
exposes this as `hasLicenseRestrictions`, so an app can show the difference rather than flattening
every model into "commercial use: yes". (The reference *code* is MIT; the *model* is not.)

**It runs on the CPU provider deliberately.** ONNX Runtime's CoreML execution provider supports
only part of these graphs — it split the vector estimator into ~134 partitions covering 702 of
1032 nodes — so the run spends its time crossing between CoreML and CPU rather than computing:

| provider | steps | session load | synthesis | speed |
|---|---|---|---|---|
| CPU | 4 | 0.28 s | 0.56 s | **11.4x** |
| CoreML | 4 | 6.53 s | 1.08 s | 5.9x |

Denoising steps default to **4**, also measured: 2 steps hits 20x real time but drops words, and
8 or 16 cost 2–4x more for no gain in intelligibility.

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
