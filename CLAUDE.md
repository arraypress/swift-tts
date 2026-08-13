# CLAUDE.md — swift-tts

On-device, commercial-safe text-to-speech for macOS/iOS. Module: **SpeechSynthesizer**. Multi-engine behind one protocol, mirroring the `swift-speech-transcriber` shape (and the same architecture as swift-llm / swift-stable-audio).

## Build & test
```bash
swift build
swift test        # 19 core tests (no GPU, no downloads)
```

## ⚠️ MLX GPU inference does not work from `swift run`

MLX-Swift can't load its Metal library from a bare SwiftPM executable — you get `Failed to load the default metallib`. This is an MLX-Swift CLI limitation, **not a bug in this package**. GPU inference needs an Xcode **app** build, which bundles `default.metallib` automatically.

Tester app: `~/Documents/Development Work/Swift/swift-tts-tester` (xcodegen + Xcode 26.6). Build it with:
```bash
xcodebuild ... -skipPackagePluginValidation -skipMacroValidation
```
Both flags are required — mlx-swift ships a CudaBuild plugin that otherwise fails validation.

## Engine status (verify before trusting — this moves)

| Engine | Backend | State |
|---|---|---|
| `AppleEngine` | `AVSpeechSynthesizer` | Real, compiled, zero download. Live render needs an app run loop (**hangs headless**) → guard-tested only. |
| `PocketTTS` | FluidAudio | ✅ **Verified — sounds correct** in the tester. The recommended CoreML/mobile engine. |
| `KokoroTTS` | FluidAudio | All 28 English voices work. Still **mispronounces** — see below. |
| `MLXTTS` (Chatterbox) | mlx-audio-swift | Compiles; downloaded (416 MB) + loaded live. GPU inference pending an Xcode app run. |
| `MLXTTS` (Qwen3) | mlx-audio-swift | Compiles; live GPU test pending. |

## Kokoro: all 28 voices now, but it still mispronounces

**Voices — fixed.** The converted repo (`FluidInference/kokoro-82m-coreml`) ships
exactly one English pack, `ANE/af_heart.bin`. The engine listed five and four of
them answered a 404 *at synthesis*, after the caller had chosen one. The other
packs are in the original `hexgrad/Kokoro-82M` as `voices/<id>.pt`, and the
tensor inside is byte-identical to what the engine wants: 510 × 256 LE float32,
522,240 bytes. `KokoroVoicePacks` fetches and caches on first use — no PyTorch,
no Python.

Read the archive through its **central directory**, not by walking local
headers. `torch.save` writes streaming with the data-descriptor flag (`0x0808`)
set, so every local header's size field is **zero**; a forward walk steps zero
bytes and lands mid-payload.

**Pronunciation — broken, and worse than "vocabulary work".** The text path
mangles **`is`**, every time, into "ice". Feed it three ordinary sentences and
the damage spreads to the words either side:

```
"This is a test. That is the plan. It is fine."
 → "Thighs ice attest that ice the planet ice fine."
```

Measured against the phoneme path with a carrier sentence, eight words each,
transcribed back with `transcribe`:

| | target word | carrier "is" |
|---|---|---|
| text (G2P) | 5/8 | **0/8** |
| phonemes (bypass) | 8/8 | 8/8 |

`colonel` scores as a phoneme-path miss only because it came back spelled
"kernel", which is the same word out loud — the audio was right.

Do not test this with isolated single words. A one-second clip of "weak"
transcribes as "weekend" on a *correct* rendering; the carrier sentence is what
makes the instrument trustworthy.

**Why:** FluidAudio's Kokoro uses a small *neural* G2P (55 graphemes, derived
from `laishere/kokoro-coreml`), **not** Kokoro's reference Misaki G2P. Proven
upstream twice over: `SpokenAudio` decode is byte-identical to FluidAudio's raw
WAV, and PocketTTS through the same pipeline sounds fine.

**This disqualifies Kokoro's *text* path outright** — not just for vocabulary
work, for prose. **Prefer PocketTTS for the CoreML tier.**

## The phoneme bypass works — proven, and shipped

`KokoroEngine.synthesize(phonemes:options:)` hands espeak-flavoured IPA
straight to `KokoroAneManager.synthesizeFromPhonemes`, skipping the G2P. That
is the 8/8 column above: the three CoreML stages behind the G2P are sound, and
this reaches them. `speak --engine kokoro --phonemes "ðə wˈɜːd ɪz tˈɜːmɔɪl."`

`KokoroPhonemes.validate` checks the string against the model's own
`vocab.json` (114 single-character symbols) **before** synthesis, because the
encoder's reference behaviour is to *silently drop* what it does not recognise
— mid-word, no error. An unchecked stray symbol is a plausible mispronunciation
you never learn about, which is the exact failure this feature exists to
escape.

**What is still missing is a G2P to feed it.** Hand-written IPA proves the
pipeline; it does not make a usable tool, and Band9's word data has no `ipa`
field. Options, in order of appetite: ship a CMUdict-style lookup table with
letter-to-sound fallback; port **Misaki** (Kokoro's reference G2P); or lift the
front end from `mweinbach/kokoro-swift`, which already does Misaki in Swift.
Until one exists, the honest recommendation stays **PocketTTS**.

`g2ptest` under scratchpad is dead — it failed with a CoreML MIL error and I
briefly took that for a platform limit. It was not: `speak` loads the same
models from a plain SwiftPM binary and always did. Test through the CLI.

## Gotchas
- **Both FluidAudio and mlx-audio-swift export their own `TTSError`.** Engines must `typealias TTSError = SpeechSynthesizer.TTSError` or the ambiguity breaks the build.
- `MLXEngine` is a `final class @unchecked Sendable`, not an actor — `SpeechGenerationModel` is a non-Sendable existential, so an actor isn't possible.

## Model curation — Apache/MIT weights only (commercial safety)

Included:
- **Kokoro-82M** (Apache) + **PocketTTS** (MIT) via **FluidAudio** — CoreML/ANE, runs on iPhone. PocketTTS adds voice cloning.
- **Chatterbox** (MIT, best-sounding) + **Qwen3-TTS** (Apache, multilingual) via **mlx-audio-swift** — MLX/GPU, Mac-class.

Deliberately excluded, do not re-add without a licence review: **Fish S2, F5-TTS, Higgs, XTTS** (non-commercial), **Orpheus** (Llama-licensed weights).

### ⚠️ The code-vs-weights trap — read before adding any model
A repo can ship **Apache-licensed code with non-commercial weights**. The top-level `LICENSE` file lies about what you actually need, because you run the *weights*, not the code. **Always check the model-weights licence specifically.**

**Fish Audio is the textbook case:** code is Apache, weights are CC-BY-NC-SA-4.0 (now a custom "Fish Audio Research License") → non-commercial, and commercial use requires a paid licence from Fish. That's the entire reason it's excluded despite the quality.

### Evaluated but not included
- **OmniVoice** (Xiaomi / next-gen Kaldi, Apache-2.0) — 646 languages, diffusion-based, ~40× realtime. Non-autoregressive, so it doesn't do token-stream instruction-following.
- **Spark-TTS** (0.5 B) — voice *creation* by attribute (gender/pitch/rate). Weights licence needs verifying before use.

### Why the emotion tags work
Chatterbox and friends are autoregressive "LLMs for audio" — they predict the next chunk of speech tokens. Inline `[laugh]`/`[sigh]` tags work because the events are **trained in** (transcripts annotate where the speaker actually laughed), so at generation the model *produces* the laugh as continuous audio with prosody flowing in and out, in the chosen voice — **not a spliced SFX clip**. The speaker embedding rides along at every step. Chatterbox uses a curated fixed tag set plus one exaggeration dial.

### Runtime routing rule of thumb
Small models (Kokoro 82 M) → **Core ML on the ANE**. Larger ones (Qwen3 0.6/1.7 B, Spark 0.5 B) → **MLX on the GPU** is the path of least resistance. Core AI (WWDC 2026) is the successor path for transformer/generative models and scales 3 B→70 B — worth revisiting when targeting macOS 27.

Real HF repos: `mlx-community/Chatterbox-TTS-fp16`, `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit`, `chatterbox-turbo-4bit` (smallest).

## Next
1. Confirm PocketTTS live on mobile.
2. Run Chatterbox/Qwen3 from the Xcode app to clear the metallib issue.
3. Tag 1.0.0 and make public.

Later: a Core AI backend (WWDC26) for OS-managed model delivery — macOS 27 / iOS 27 only.

## Conventions
- Private repo (`arraypress/swift-tts`).
- Commit only when asked; branch off `main` first if needed.
