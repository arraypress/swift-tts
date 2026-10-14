# Swift TTS (SpeechSynthesizer)

On-device text-to-speech for macOS and iOS. One engine protocol, curated open models — commercial-safe by default, plus two opt-in models under restricted licences (Drama 3, OmniVoice) — the text-to-speech counterpart to a multi-engine transcriber, where every backend returns the same `SpokenAudio` regardless of which model produced it.

Models are **downloaded on first use** and cached, so the app ships small and every later run is fully offline.

## The models

All but the two opt-in ones are commercial-safe (Apple's system voices, or Apache-2.0 / MIT / CC BY 4.0 *weights*) and they split by runtime tier:

| Model | License | Runtime | Runs on iPhone? | Cloning | Status | Best for |
|---|---|---|---|---|---|---|
| **Apple (system)** | Apple (free to use) | System | ✅ | — | ✅ built-in | zero-config default & fallback, every device |
| **Kokoro-82M** | Apache-2.0 | CoreML / ANE | ✅ | — | ✅ **verified** (live audio) | fast, light (9 langs, SSML) |
| **PocketTTS** | CC BY 4.0 weights (credit Kyutai; code MIT) — voices `cosette`, `jean` CC BY-NC | CoreML | ✅ | ✅ | ✅ **verified** (live audio) | small + cloning on mobile |
| **Chatterbox** | MIT | MLX / GPU | ❌ Mac | ✅ | ✅ compiled | best-sounding, emotion + 10s cloning |
| **Qwen3-TTS** | Apache-2.0 | MLX / GPU | ❌ Mac | ✅ | ✅ compiled | multilingual, long-form |
| **Supertonic 3** | ⚠️ OpenRAIL-M | ONNX Runtime | ✅ | — | ✅ **verified** (live audio) | 31 languages on mobile, 11x real time |
| **Drama 3** (opt-in) | ⛔ Fish Audio Community License | MLX / GPU, 36 GB Mac | ❌ | ✅ | ✅ **verified** (parity + live audio) | expressive scenes: inline cues, speaker turns |
| **OmniVoice** (opt-in) | ⛔ CC BY-NC + Boson Higgs Audio 2 Community License | MLX / GPU, 16 GB Mac | ❌ | ✅ | ✅ **verified** (probe parity + live audio) | 600+ languages, designed voices, audiobooks |

> **License hygiene:** the default models are Apple's system voices and Apache/MIT/CC BY/OpenRAIL-*weights* models. **PocketTTS's weights are CC BY 4.0, not MIT** (only its code is MIT; kyutai/pocket-tts model card): commercial use is fine with credit to Kyutai (`TTSModel.attribution`). Two of its 21 English preset voices, **`cosette` (Expresso) and `jean` (EARS), are CC BY-NC 4.0 — non-commercial only**; `TTSVoice.license` and `isCommercialUseAllowed` say so per voice, and the default (`alba`, CC BY 4.0) is pinned so neither can become it. **Drama 3 and OmniVoice are the exceptions, and both are opt-in**: neither engine will start until the caller names its licence version (below). Other restrictive models (Fish S2, F5-TTS, Higgs Audio as a TTS model, XTTS) and Llama-licensed weights (Orpheus) are deliberately **not** supported.

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

## OmniVoice — opt-in, restricted licences, 16 GB Macs

`import OmniVoiceTTS`. [k2-fsa/OmniVoice](https://huggingface.co/k2-fsa/OmniVoice): a diffusion language model over a Qwen3 backbone writing nine codebooks of Boson's Higgs Audio 2 tokens at 24 kHz — **600+ languages**, a **voice designed from fixed words**, or one **cloned** from a clip and its transcript. The network is [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift)'s port (`OmniVoiceModel`, used as is); this engine adds what the port leaves to its caller and the reference implementation does itself: the voice-design vocabulary check, language codes, splitting long text with the first piece as the voice for the rest, the reference's audio clean-up, tags tokenized the way the model was trained, and a licence gate.

```swift
import OmniVoiceTTS

let engine = try OmniVoiceEngine(modelDirectory: folder, licence: OmniVoiceLicence.version)  // naming it is accepting it
try await engine.prepare()                                    // ~1 s from a warm disk
var settings = OmniVoiceSettings(voiceDesign: "male, elderly, low pitch, british accent", seed: 7)
let (audio, report) = try await engine.synthesize("Good evening. [laughter] Do come in.", settings: settings)
settings.reference = OmniVoiceReference(audio: clip, transcript: "Exactly what is said in the clip.")
for try await piece in engine.chunks(longText, settings: settings) { /* append piece.samples */ }
```

**The licences.** Two sets of weights, neither open. The speech model is **CC BY-NC** (the model card names no version; "due to constraints from its training data") — non-commercial only. Its audio tokenizer is Boson AI's Higgs Audio 2, under the **Boson Higgs Audio 2 Community License**, built on the Meta Llama 3 Community License: Llama 3's Acceptable Use Policy applies, its output may not be used to improve another large language model, above 100,000 annual active users a licence from Boson is required, and both licence texts and a NOTICE travel with anything that uses it — they are in [LICENSES/](LICENSES/) and compiled in as `OmniVoiceLicence.higgsAudioLicenceText` / `.llama3LicenceText` / `.notice`. The model card forbids unauthorised cloning and impersonation. (The mlx-community conversion's card says apache-2.0: that is the *code's* licence.) `OmniVoiceEngine` throws `licenceNotAccepted` unless handed `OmniVoiceLicence.version`, and refuses Macs under 16 GB. It downloads nothing; the caller supplies the folder (the `speak` CLI fetches it pinned and checksummed).

> Built with Higgs Materials licensed from Boson AI USA, Inc., Copyright Boson AI USA, Inc., All Rights Reserved and Meta Llama 3 licensed under the Meta Llama 3 Community License, Copyright Meta Platforms, Inc., All Rights Reserved. Based on Meta Llama 3.

**Which weights.** [mlx-community/OmniVoice](https://huggingface.co/mlx-community/OmniVoice) (float32, 3.27 GB, pinned at `defe4bdc`) — the only conversion whose audio tokenizer keeps the semantic encoder, which encoding *any* reference needs: a clone, and the first piece of a long text that the rest are voiced from. The bfloat16 conversion (1.63 GB) strips it, and the port casts every weight to float32 on load anyway, so it would save disk, not memory; the 8-bit one does not load (the port has no quantized layers). So: one download, float32 on disk, and the engine then holds the speech model in **bfloat16** (`precision: .bfloat16`, the default; `.float32` is the port's own).

**Voice design is a closed vocabulary** — one word per category, comma-separated: gender (`male`, `female`); age (`child`, `teenager`, `young adult`, `middle-aged`, `elderly`); pitch (`very low pitch` … `very high pitch`); `whisper`; ten English accents (`british accent`, `indian accent` …); twelve Chinese dialects (`四川话` …). `VoiceDesignVocabulary.resolve` is the reference's own check, ported: anything else is refused with the list and the nearest word ("did you mean 'british accent'?"), two words from one category are refused, and Chinese text turns the words Chinese, as the reference does. There is deliberately no free-text mapper — the caller picks the words. Measured in the reference: "high"/"very high pitch" go breathy rather than higher (a female voice: 267 Hz at moderate, 216 at high, 179 at very high). Here, the same design and seed repeat bit for bit.

**Tags.** Only thirteen are trained: `[laughter]`, `[sigh]`, `[confirmation-en]`, `[question-en|ah|oh|ei|yi]`, `[surprise-ah|oh|wa|yo]`, `[dissatisfaction-hnn]`; uppercase CMU phonemes in brackets (`[B EY1 S]`) override a pronunciation. Anything else in brackets is **read aloud** ("[whispers]" → "Whispers"), so `OmniTags.filter` removes it (and Drama's `{cues}` and `<|speaker:N|>`), reporting what went. Question tags are moved, because where they sit decides whether the clip survives — measured over four seeds each, transcribed back:

| written | clips that came out as noise |
|---|---|
| `You are leaving already [question-en]` | 2 / 4 |
| `You are leaving already? [question-en]` | 4 / 4 |
| `You are leaving already. [question-en]` | 4 / 4 |
| `[question-en] You are leaving already?` | 3 / 4 |
| `You are leaving already [question-en]?` | **0 / 4** (and 0 / 4 on four more seeds) |
| `You are leaving already [question-en] so soon?` | 0 / 4 |

so every one of the broken forms is rewritten to the `words [question-xx]?` form; `[question-ah]` there still lost its words once in four. Confirmation, surprise, laughter and sigh tags were not affected and stay where they are. Tags are tokenized standalone, as the reference does (`TagAwareTokenizer` wraps the port's tokenizer) — inline, Qwen's pre-tokenizer glues the space before a tag to its bracket.

**Languages.** `OmniLanguages.resolve` takes a code from the model's table (646), a name ("Welsh", "Cantonese") or a BCP-47 tag ("pt-BR", "ar" → `arb`); unknown is an error. Without one the model detects the language. **Thai and Khmer are tokenized differently** by swift-transformers than by the reference (25 languages in 18 scripts compared token for token against Hugging Face `tokenizers`; only these two differ — Swift's BPE returns whole words the reference splits), and the model drops words: Thai round-tripped at 51 % character error against the reference's 4 %. `OmniText.tokenizerCaveat` flags such text.

**Long text** is split as the reference splits it — when the estimate passes 30 s, at punctuation into ~15 s pieces, never after "Mr." — and, unless a voice is cloned, the first piece becomes the reference for the rest so the voice does not drift. `chunks()` streams the pieces, so long text is never held whole; each piece gets the reference's clean-up (pauses over 1 s cut to 1 s, edges trimmed to 100 ms, 100 ms fades, 100 ms between pieces).

### Measured (M3 Max, 36 GB)

Against the probe's PyTorch reference clips (same text, voice design, language and seed — PyTorch and MLX seeds do not produce the same audio, so this compares measurements, not samples), transcribed back with `transcribe`:

| Measure | reference (PyTorch fp32) | Swift, float32 | Swift, bfloat16 |
|---|---|---|---|
| designs, repeats, clones (17 English clips) | 0 % WER | 0 % WER | 0 % WER |
| es · fr · de · zh · ar | 0 % | 0 % | 0 % |
| ja (CER, Apple / Whisper) | 5.7 % / 0 % | 5.7 % / 0 % | 5.7 % / 0 % |
| cy · sw (Whisper) | 16 % · 11 % | 11 % · 11 % | 21 % · 28 % |
| th (CER, Whisper) | 4 % | 51 % | 54 % |
| clone of a `say` voice, median pitch (ref Daniel 114 Hz, Karen 191 Hz) | 112–117 · 188–190 | 113–115 · 188–192 | 114–116 · 185–187 |
| British elderly male design, median pitch | 88 Hz | 92 Hz | 91 Hz |
| same design + seed, three times | identical | identical | identical |

(Welsh and Swahili are one clip each and the judge is the weak link there; the bfloat16 numbers move within that noise.)

**Speed and memory.** Loading takes 0.9–1.4 s from a warm disk. Generation, real-time factor over five sentences — **measured while another agent ran FLUX image generation on the same GPU for most of the session**, so these are medians with the best runs in brackets, not clean figures:

| Steps | float32 | bfloat16 (default) |
|---|---|---|
| 32 steps (reference default) | 0.7× (≤1.4×) | 1.4× (≤2.4×) |
| 16 steps | 1.7× (≤2.6×) | 1.6× (≤2.5×) |
| peak footprint | 5.8–6.0 GB | 3.7–4.3 GB |

The Python MLX probe (bfloat16, uncontended) reached 2.95× at 32 steps and 5.55× at 16; the port runs the conditional and unconditional passes one after the other rather than as a batch, which is likely most of the gap. Streamed to disk a piece at a time, a 29-minute chapter peaked at 5.65 GB and a 4-minute one at 5.68 GB (sampled every 30 s through the long one: median 2.8 GB, the highest spike in its last third no higher than in its first) — the footprint does not grow with length.

## Status

- ✅ **Core (`SpeechSynthesizer`) — built + unit-tested.** `SpokenAudio` WAV encode/decode, `TTSModel` metadata/licensing, `SynthesisOptions`, errors. Zero deps.
- ✅ **AppleEngine — real, in the core, tested live.** `AVSpeechSynthesizer`; no download, every device. **3.0.1 fixed dropped speech:** the buffer callback hands back an empty buffer at the end of *every* stretch it synthesises, not just the last, and the engine stopped at the first — a 144-word paragraph came back as 12.4 s of its 40.1 s. It now ends on the delegate's `didFinish`. Tested against `say` (same voice: 40.1 s and 40.1 s) and transcribed back at 0.7 % word error (was 67 %).
- ✅ **KokoroTTS — verified end-to-end** (downloads + produces 24 kHz audio). ⚠️ **Pronunciation caveat:** FluidAudio 0.15.2's Kokoro uses a small *neural* G2P (not Kokoro's reference Misaki G2P) and mispronounces some words ("Hello" → "Hi hoy"). The audio path is correct (verified byte-identical to FluidAudio's raw output); the garbling is upstream in FluidAudio's G2P. Prefer PocketTTS for the CoreML tier until FluidAudio's Kokoro G2P improves. **Long text (3.0.1):** the model takes at most 510 phonemes a pass and used to throw `phonemeSequenceTooLong`; the engine now cuts text over 300 characters at sentence ends, then clause marks, then spaces, speaks each piece with a 0.25 s gap, and halves any piece that still overflows. The 144-word paragraph that failed: 47.0 s in three pieces, 9.7 % word error (the G2P's, not the cutting's).
- ✅ **PocketTTS — verified, sounds correct.** FluidAudio 0.15.2; the recommended CoreML/mobile engine (CC BY 4.0 weights, cloning). Runs the same pipeline as Kokoro and sounds right. All 21 English presets are listed (3.0.1; it used to offer one), each with its licence.
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

Covers the core: WAV encoding (header, sample rate, clamping), model licensing/runtime invariants, options clamping, and errors — for Drama 3 the text chunking against the reference's own outputs, the licence and memory gates, the frame budget and the dead-air rule — and for OmniVoice the vocabulary, tag filtering and question-tag placement, language codes, chunking, audio clean-up, the licence and memory gates and the model-folder checks (36 tests, no model). The model tests and the parity probes need weights, so they are opt-in:

```bash
DRAMA_MODEL=<model folder> DRAMA_REFERENCE=<dump folder> swift test --filter "DramaParity|DramaStepParity"
DRAMA_MODEL=<model folder> DRAMA_LONG_CODES=<codes.safetensors> swift test --filter DramaCodecStream
OMNIVOICE_MODEL=<mlx-community/OmniVoice folder> swift test --filter OmniVoiceModelTests
```

## Requirements

- macOS 14+ / iOS 17+ (the core). Individual engines raise this — FluidAudio and MLX target newer OSes; a Core AI backend (WWDC 2026) would require macOS 27 / iOS 27.
- Drama 3: Apple silicon with **36 GB** of memory or more, and 24 GB of disk for the model.
- OmniVoice: Apple silicon with **16 GB** of memory or more, and 3.3 GB of disk for the model.
- Swift 6.0+

## License

MIT License (this package) — see LICENSE. Each **model's** weights carry their own licence; see the table above. Drama 3's weights are under the Fish Audio Community License v1.0 (Copyright © 39 AI, INC.), which this package does not redistribute; OmniVoice's are CC BY-NC (Xiaomi Corp. and the OmniVoice authors) with Boson AI's Higgs Audio 2 tokenizer under the Boson Higgs Audio 2 Community License and the Meta Llama 3 Community License (texts and NOTICE in [LICENSES/](LICENSES/)), also not redistributed — `OmniVoiceTTS` ports parts of k2-fsa/OmniVoice's Apache-2.0 code (voice-design check, text chunking, duration rule, audio clean-up); `DramaTTS` is a port of `fish_drama3` from [mlx-audio](https://github.com/Blaizzy/mlx-audio) (MIT, Copyright (c) 2024 Prince Canuma), and reuses mlx-swift-lm (MIT, Copyright (c) 2024 ml-explore) and mlx-audio-swift (MIT, Copyright (c) 2025 Prince Canuma). Built with Fish Audio.

## Author

Created by David Sherlock ([ArrayPress](https://github.com/arraypress)) in 2026.
