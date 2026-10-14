# Swift TTS (SpeechSynthesizer)

On-device text-to-speech for macOS and iOS. One engine protocol, curated open models — commercial-safe by default, plus one opt-in model under a restricted licence (Drama 3) — the text-to-speech counterpart to a multi-engine transcriber, where every backend returns the same `SpokenAudio` regardless of which model produced it.

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
| **Drama 3** (opt-in) | ⛔ Fish Audio Community License | MLX / GPU, 36 GB Mac | ❌ | ✅ | ✅ **verified** (parity + live audio) | expressive scenes: inline cues, speaker turns |

> **License hygiene:** the default models are Apple's system voices and Apache/MIT/OpenRAIL-*weights* models. **Drama 3 is the one exception, and it is opt-in**: its engine will not start until the caller names its licence version (below). Other restrictive models (Fish S2, F5-TTS, Higgs, XTTS) and Llama-licensed weights (Orpheus) are deliberately **not** supported.

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

let engine = SupertonicEngine()             // downloads ~382 MB on first prepare(), from arraypress/tts-supertonic-3
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

## Drama 3 — opt-in, restricted licence, 36 GB Macs

`import DramaTTS`. Fish Audio's [Drama 3](https://huggingface.co/fishaudio/drama-3): a 35B mixture-of-experts backbone (3B active; Qwen3.5-MoE, gated-delta + full attention), a codebook audio tower and Fish's 44.1 kHz DAC codec — ported to MLX in Swift from mlx-audio's `fish_drama3` and run from the 4-bit community conversion ([stickerdaniel/drama-3-mlx-4bit](https://huggingface.co/stickerdaniel/drama-3-mlx-4bit), pinned at `06469309`). Delivery cues go inline, where they should happen; speakers are tags; a voice is cloned from a clip **and its transcript**.

```swift
import DramaTTS

let engine = try DramaEngine(modelDirectory: folder, licence: DramaLicence.version)  // naming it is accepting it
try await engine.prepare()                                   // 22 GB into memory, ~5 s
let audio = try await engine.synthesize(
    "<|speaker:0|> Are you coming tonight? <|speaker:1|> [sighs] I'd love to, but I'm exhausted.")
for try await piece in engine.chunks("[whispering] Don't tell anyone.") { /* play piece.samples as they come */ }
```

**The licence** — the Fish Audio Community License v1.0, not an open licence: free for research and non-commercial use; commercial use only while your organisation's annual revenue is under US$500,000; **never as a hosted service** where others generate speech or clone voices from text or samples they supply; **never to imitate an identifiable person's voice without their consent**; anything shipped with it must say "Built with Fish Audio". `DramaEngine` throws `licenceNotAccepted` unless handed `DramaLicence.version`, and refuses Macs under 36 GB (`insufficientMemory`). The engine does not download: the model folder comes from the caller (the `speak` CLI fetches it, pinned and checksummed). **Built with Fish Audio.**

### Measured (M3 Max, 36 GB)

**Parity with the Python reference** (mlx-audio `fish_drama3`, mlx 0.32.3, same inputs):

| check | Swift vs Python | Python vs itself* |
|---|---|---|
| tokenizer / prompt frames | 8/8 identical, 8/8 identical | — |
| text chunking (12 cases, incl. CRLF, CJK, tags) | identical | — |
| backbone hidden cosine, teacher-forced (mean / min) | 0.9993 / 0.9949 · 0.9987 / 0.9834 | 0.9992 / 0.9937 · 0.9988 / 0.9896 |
| semantic token top-1 agreement | 92.7 % · 97.4 % | 92.7 % · 85.9 % |
| tower top-1 agreement (9 codebooks) | 92.8 % · 92.5 % | 92.0 % · 91.8 % |
| single-frame decode path (cosine mean; semantic, tower) | 0.9993; 94.4 %, 92.3 % | — |
| each of the 40 layers alone, fed Python's input | cosine ≥ 0.999998 | — |
| codec decode, whole / streamed in 1-, 16-, 64-frame pieces | 117–119 dB SNR / 117–118 dB SNR | — |

\* the same Python pass prefilled 32 rows at a time instead of 64 — the noise floor of a bfloat16 4-bit model. The port sits inside it; per layer it is exact to bfloat16 rounding, and the drift is rounding amplified through 40 layers, as in the reference itself. Two probe lines (`01-plain`, 108 frames · `06-angry`, 77 frames).

**Free-running:** the eight probe lines (plain, `[stressed]`, `{feeling stressed}`, start-of-line `[whispering]`, mid-line `[shaky breath]`, `[angry]`, a two-speaker dialogue, Spanish) transcribed back word-for-word, 8/8. Cloning from a synthetic `say` voice: the Daniel clip (median pitch 109 Hz) came back at 115–122 Hz, Karen (188 Hz) at 210 Hz, against 285–306 Hz unreferenced — and word-perfect.

**Speed and memory:** loading takes 5–6 s; in a warm process generation runs **1.6–1.7× real time** on a quiet Mac (1.1–1.5× with a browser open; the Python reference: 1.8×), first audio **0.6–0.8 s**. The first clip in a process pays 3–8 s of GPU warm-up (13 s on the very first run of a new binary). **Peak footprint 25.8 GB**: MLX's buffer cache is capped at 256 MB once the model loads (29.2 GB uncapped, no speed lost); the Python reference peaked at 29–33 GB.

### Runaways, and the rewind that fixes them

Drama 3 sometimes never says end-of-speech: one sentence, then steady hiss until the frame cap (the reference caps at 1024 frames, 47.6 s). Measured on four lines × five seeds, **9 of 20 clips ran away — in the Python reference and in this port alike**, with or without a cue at the start of the line, so it is the model and recipe, not the port. Two guards:

- **A frame budget scaled to the text** — 3 s plus 4 frames per UTF-8 byte (speech measured 1.16–1.45 frames per byte), never above 1024.
- **Dead-air detection with rewind.** Hiss is not silence: it sat at −34 to −81 dBFS, louder than some whispers, but flat — the 50 ms levels inside a second of hiss spread ≤ 1.2 dB, while speech (whispers included) never spread under 2.9 dB, quiet speech never under 5.0. Two seconds of audio quieter than −45 dBFS, or quieter than −30 dBFS and flatter than 2.5 dB, is a runaway (the longest real pause measured was 1.0 s). Dead air is held back, never played; generation **rewinds to the end of the last speech** — caches, history and codec state — and samples again, up to three times. With it, **19 of the 20** clips came back complete; the twentieth lost its last sentence after three rewinds.

`DramaReport` counts rewinds, chunks that still ended in dead air, and chunks that hit their cap. Whether the bfloat16/8-bit checkpoint runs away less is untested (it is a ~70 GB conversion).

**`[brackets]` vs `{braces}`:** with a fixed (cloned) voice, plain, `[stressed]` and `{feeling stressed}` measured the same — level within 0.3 dB, pitch within 1 Hz and 0.3 semitones of spread, length within 2 % (four seeds each). Unreferenced, `{feeling stressed}` came out 2 dB louder, higher (190 vs 134 Hz) and 8 % faster, `[stressed]` in between — mostly a different voice being picked.

### Not done

- Streaming playback is wired (`chunks`), but listened to only through files.
- The engine has no rate control (Drama 3 has none) and no named voices.

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

**Where the weights come from (1.3.0).** An unmodified mirror,
[arraypress/tts-supertonic-3](https://huggingface.co/arraypress/tts-supertonic-3), of
Supertone/supertonic-3 at commit `3cadd1ee`, every file checked against Supertone's published
hashes and pinned by commit. It used to follow Supertone's own `main`, which could change under the
tools. OpenRAIL-M: the licence's use restrictions (Attachment A) apply to anyone using the voice.

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

Covers the core: WAV encoding (header, sample rate, clamping), model licensing/runtime invariants, options clamping, and errors — and for Drama 3 the text chunking against the reference's own outputs, the licence and memory gates, the frame budget and the dead-air rule. The parity probes need the model and Python's dumps, so they are opt-in:

```bash
DRAMA_MODEL=<model folder> DRAMA_REFERENCE=<dump folder> swift test --filter "DramaParity|DramaStepParity"
DRAMA_MODEL=<model folder> DRAMA_LONG_CODES=<codes.safetensors> swift test --filter DramaCodecStream
```

## Requirements

- macOS 14+ / iOS 17+ (the core). Individual engines raise this — FluidAudio and MLX target newer OSes; a Core AI backend (WWDC 2026) would require macOS 27 / iOS 27.
- Drama 3: Apple silicon with **36 GB** of memory or more, and 24 GB of disk for the model.
- Swift 6.0+

## License

MIT License (this package) — see LICENSE. Each **model's** weights carry their own licence; see the table above. Drama 3's weights are under the Fish Audio Community License v1.0 (Copyright © 39 AI, INC.), which this package does not redistribute; `DramaTTS` is a port of `fish_drama3` from [mlx-audio](https://github.com/Blaizzy/mlx-audio) (MIT, Copyright (c) 2024 Prince Canuma), and reuses mlx-swift-lm (MIT, Copyright (c) 2024 ml-explore) and mlx-audio-swift (MIT, Copyright (c) 2025 Prince Canuma). Built with Fish Audio.

## Author

Created by David Sherlock ([ArrayPress](https://github.com/arraypress)) in 2026.
