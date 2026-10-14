# CLAUDE.md — swift-tts

On-device, commercial-safe text-to-speech for macOS/iOS. Module: **SpeechSynthesizer**. Multi-engine behind one protocol, mirroring the `swift-speech-transcriber` shape (and the same architecture as swift-llm / swift-stable-audio).

## Build & test
```bash
swift build
swift test        # unit tests, no GPU, no downloads; the Apple long-text tests speak live and need `say` (`transcribe` optional)
```

## MLX runs from plain `swift build` (the old "needs an Xcode app" note was wrong)

Measured fleet-wide (2026-09-03) and again by DramaTTS (2026-10-14): `swift build`/`swift test` link
MLX and run Metal; SwiftPM puts `mlx-swift_Cmlx.bundle` beside the binary, and a shipped CLI carries it.

Tester app: `~/Documents/Development Work/Swift/swift-tts-tester` (xcodegen + Xcode 26.6). Build it with:
```bash
xcodebuild ... -skipPackagePluginValidation -skipMacroValidation
```
Both flags are required — mlx-swift ships a CudaBuild plugin that otherwise fails validation.

## Engine status (verify before trusting — this moves)

| Engine | Backend | State |
|---|---|---|
| `AppleEngine` | `AVSpeechSynthesizer` | Real, zero download, **tested live** (`AppleLongTextTests`, against `say` + `transcribe`). The old "hangs headless" note was wrong: buffers and `didFinish` arrive on the main queue, which `swift test` and an async CLI both service. |
| `PocketTTS` | FluidAudio | ✅ **Verified — sounds correct** in the tester. The recommended CoreML/mobile engine. Weights **CC BY 4.0** (not MIT). |
| `KokoroTTS` | FluidAudio + `MisakiG2P` | All 28 English voices work, and it **reads correctly since 3.1.0** (Misaki port, below). speak's default engine from 0.4.0. |
| `MLXTTS` (Chatterbox) | mlx-audio-swift | Compiles; downloaded (416 MB) + loaded live. GPU inference pending an Xcode app run. |
| `MLXTTS` (Qwen3) | mlx-audio-swift | Compiles; live GPU test pending. |

## AppleEngine: end on `didFinish`, never on an empty buffer (3.0.1)

`write(_:toBufferCallback:)` hands back a **zero-length buffer at the end of every stretch** it
synthesises, not only at the end. Measured on a 144-word paragraph: four empty buffers, after
12.4 s, 22.9 s, 32.6 s and 40.1 s of audio, then `didFinish` straight after the last. The engine
used to stop at the first, so long text came back as its opening sentences (and audiobook mode
skipped sentences). It now accumulates across empty buffers and resumes on the delegate's
`didFinish` (`didCancel` → error). Probe: `scratchpad/probe-apple` in the 2026-10-14 session.

## Kokoro: long text is cut into pieces (3.0.1)

The CoreML chain takes **510 phonemes** a pass (and 2,000 acoustic frames ≈ 50 s);
FluidAudio throws `phonemeSequenceTooLong` beyond. Its `G2PModel` is internal, so phonemes cannot
be counted ahead: `KokoroText` cuts by characters (300 ≈ 300 phonemes; measured 775 chars → 745
phonemes) at sentence ends → clause marks → spaces, the engine speaks each with a 0.25 s gap
(FluidAudio strips punctuation, so there is no pause of its own), and halves any piece that still
throws `phonemeSequenceTooLong`/`acousticFramesExceedCap`. **Kokoro's CoreML graphs crash inside
the test runner** (`shape for TensorData is not static`) — live Kokoro tests run the `speak`
binary from speak's own suite.

## PocketTTS licence: CC BY 4.0 weights, two NC voices (3.0.1)

The model card (kyutai/pocket-tts, gated; read via the HF API) says `license: cc-by-4.0`; only the
GitHub code is MIT. Credit Kyutai (`TTSModel.attribution`). Preset voices keep their recordings'
terms (huggingface.co/kyutai/tts-voices README): VCTK + alba-mackenna CC BY 4.0, voice-donations +
voice-zero CC0, **Expresso → `cosette` and EARS → `jean` are CC BY-NC 4.0**. `PocketVoices` lists
the 21 English presets with licences; `defaultID` (`alba`) is passed explicitly so FluidAudio
cannot change the default under us. Sizes measured from a fresh download into an empty home:
Kokoro 224 MB, Pocket 984 MB (plus ~450 MB of CoreML compile cache in ~/Library/Caches/<app>).

## Kokoro reads through Misaki (3.1.0) — the history below is why

- `MisakiG2P` (Support/) = Misaki 0.9.4 en.py: gold → silver lookup with grow_dictionary variants, apply_stress,
  special cases (a/an/am/I/to/in/the/used), -s/-ed/-ing on known stems, NNP letter spelling, ɾ→T ʔ→t (Kokoro 1.0
  is Misaki v1). spaCy tags are guessed from the previous word (verb cues, determiners, number words). Output
  matches Python Misaki byte-for-byte on the bake-off narration (`MisakiG2PTests`, enabled when the lexicon exists).
- Lexicons: `~/.cache/fluidaudio/Models/kokoro/{us,gb}_{gold,silver}.json` — FluidAudio's g2p-only download
  already fetches every root .json; it never reads them. `b…` voices use gb.
- `NeuralG2P` re-implements FluidAudio's internal `G2PModel` (BART, cpuOnly) for OOV words only.
- `SpokenText.normalize` (SpeechSynthesizer/Support) runs first, in Kokoro and Pocket; Apple does its own.
- `KokoroFiles.isDownloaded()` checks FluidAudio's `ModelNames.*.requiredModels` + the lexicons — `isDownloaded`
  is on `TTSEngine` now (default: `isReady` for downloadable models, `true` otherwise).
- Measured on the bake-off texts with `transcribe`: WER 26.8 % → 9.3 %, numbers 1 → 9/11 (the 2 misses are
  scorer/transcriber artefacts), long paragraph 9.7 % → 0.7 %. Python Misaki phonemes via `--phonemes`: 0.9 %.
- Trap: do not judge numbers by the bake-off scorer alone — it NFKD-strips "£", so "£82.99" never matches.

## Kokoro: all 28 voices now (the pronunciation notes below are pre-3.1.0 history)

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

~~This disqualifies Kokoro's *text* path outright.~~ Fixed in 3.1.0 by `MisakiG2P` (above).

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

**What was missing was a G2P to feed it** — now `MisakiG2P`. Hand-written IPA proves the
pipeline; it does not make a usable tool, and Band9's word data has no `ipa`
field. Options, in order of appetite: ship a CMUdict-style lookup table with
letter-to-sound fallback; port **Misaki** (Kokoro's reference G2P); or lift the
front end from `mweinbach/kokoro-swift`, which already does Misaki in Swift.
(Misaki was ported; PocketTTS is no longer the only honest CoreML recommendation.)

`g2ptest` under scratchpad is dead — it failed with a CoreML MIL error and I
briefly took that for a platform limit. It was not: `speak` loads the same
models from a plain SwiftPM binary and always did. Test through the CLI.

## DramaTTS (Fish Audio Drama 3) — opt-in, 2026-10-14

- Licence-gated twice: `DramaEngine(modelDirectory:licence:)` throws unless passed `DramaLicence.version`;
  refuses < 36 GB Macs. Never the default anywhere. `speak` adds the person-at-a-TTY acceptance.
- Ported from mlx-audio `fish_drama3` (Python, MIT). Backbone written here (mlx-swift-lm's Qwen35 takes
  token ids only and its layers are internal); reuses mlx-swift-lm's `gatedDeltaUpdate` + `SwitchGLU`
  and mlx-audio-swift's `FishS1DAC` weights. **mlx-swift must be ≥ 0.32 (mlx 0.32.x)** to match the
  reference: on 0.31.6 layer 0 already drifted.
- Parity is within the reference's own noise floor (Python vs Python with another prefill chunk size
  agrees only 86–93 % on semantic top-1). Judge any change against that floor, not against 100 %.
- `CodecStream` = exact streaming decode (FishS1DAC only decodes whole sequences; overlap decoding
  with 64 frames of context scored 6.5 dB SNR — the codec transformer looks back up to 1,024 frames).
- Runaways (no EOS, steady hiss) hit 9/20 clips in Python AND Swift. Fixed by the dead-air rule
  (level OR flat 50 ms-level spread, thresholds measured) + rewind to the last speech, ≤ 3 times → 19/20.
- MLX buffer cache capped at 256 MB on prepare: footprint 29.2 → 25.8 GB, same speed.
- Parity probes are opt-in env-var tests (`DramaParity`, `DramaStepParity`, `DramaCodecStream`).

## OmniVoiceTTS (k2-fsa OmniVoice) — opt-in, 2026-10-14

- Wraps mlx-audio-swift 0.1.5's port (`OmniVoiceModel`); does NOT fork it. Adds what the port leaves
  out and the reference does: `_resolve_instruct` vocabulary check (`VoiceDesignVocabulary`), language
  codes (`OmniLanguages`, 646 from lang_map.py), text chunking + first-piece-as-reference
  (`OmniText`, `keepsVoiceAcrossChunks`), reference prep and output clean-up (`OmniAudio`), and
  tag-standalone tokenization (`TagAwareTokenizer` wraps the port's public `tokenizer`).
- The port loads only via `HubCache.default`/mlx-audio/<owner_name>/ and downloads on a miss.
  `OmniModelFolder.load` links the caller's folder's files there under a fake repo name (a folder of
  per-file symlinks: the port lists by URL, which does not follow a symlinked last component →
  404 "Repository not found"), loads with stdout → /dev/null (the port `print`s), then unlinks and
  rmdirs only folders it created.
- Weights: mlx-community/OmniVoice (fp32, 3.27 GB) is the only conversion with the semantic encoder
  (cloning, and one voice across pieces of long text). The port casts every weight to float32 on load,
  so bf16 *downloads* save disk, not memory. `-8bit` is unloadable (no quantized layers in the port).
- Question tags: measured — last on a line or after the punctuation they turn clips to noise; moved
  to "words [question-xx]?" by `OmniTags.placeQuestionTags`. Unknown brackets are read aloud → removed.
- Gate like Drama: `OmniVoiceEngine(modelDirectory:licence:)` needs `OmniVoiceLicence.version`; 16 GB floor.

## Gotchas
- **Both FluidAudio and mlx-audio-swift export their own `TTSError`.** Engines must `typealias TTSError = SpeechSynthesizer.TTSError` or the ambiguity breaks the build.
- `MLXEngine` is a `final class @unchecked Sendable`, not an actor — `SpeechGenerationModel` is a non-Sendable existential, so an actor isn't possible.

## Model curation — Apache/MIT weights only (commercial safety)

Included:
- **Kokoro-82M** (Apache) + **PocketTTS** (CC BY 4.0 weights, credit Kyutai; code MIT; voices cosette + jean CC BY-NC) via **FluidAudio** — CoreML/ANE, runs on iPhone. PocketTTS adds voice cloning.
- **Chatterbox** (MIT, best-sounding) + **Qwen3-TTS** (Apache, multilingual) via **mlx-audio-swift** — MLX/GPU, Mac-class.

Deliberately excluded, do not re-add without a licence review: **Fish S2, F5-TTS, Higgs, XTTS** (non-commercial), **Orpheus** (Llama-licensed weights).
**Drama 3** passed that review on 2026-10-14 (the user asked for it) as an OPT-IN engine behind its licence; it is not commercial-safe and must never become a default.

### ⚠️ The code-vs-weights trap — read before adding any model
A repo can ship **Apache-licensed code with non-commercial weights**. The top-level `LICENSE` file lies about what you actually need, because you run the *weights*, not the code. **Always check the model-weights licence specifically.**

**Fish Audio is the textbook case:** code is Apache, weights are CC-BY-NC-SA-4.0 (now a custom "Fish Audio Research License") → non-commercial, and commercial use requires a paid licence from Fish. That's the entire reason it's excluded despite the quality.

**OmniVoice** passed the same review on 2026-10-14 (the user asked for it) as an OPT-IN engine
(`OmniVoiceTTS`): the old note here called it Apache-2.0 — that is its *code*; its weights are
**CC BY-NC**, and its audio tokenizer (Boson Higgs Audio 2) is under the Llama-3-derived **Boson Higgs
Audio 2 Community License**. The code-vs-weights trap again.

### Evaluated but not included
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
