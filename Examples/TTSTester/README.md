# TTSTester

A SwiftUI app that runs the same text through every engine this package
ships, so they can be compared side by side.

| Choice | Engine |
|---|---|
| Apple (system) | `AppleEngine` — AVSpeechSynthesizer |
| Kokoro · CoreML/ANE | `KokoroEngine` |
| Kokoro · MLX/GPU | `MLXEngine.kokoro()` — Misaki G2P |
| PocketTTS · CoreML | `PocketEngine` |
| Chatterbox · MLX/GPU | `MLXEngine.chatterbox()` — voice cloning |
| Qwen3-TTS · MLX/GPU | `MLXEngine.qwen3()` |

## Build

The Xcode project is generated, not committed — `project.yml` is the source
of truth.

```bash
cd Examples/TTSTester
xcodegen generate
open TTSTester.xcodeproj
```

Each engine downloads its own model on first run, so the first synthesis per
engine is slow and needs a network connection.

## Why it's here

It lived as a standalone folder outside version control, which meant the one
place recording how to construct all six engines was also the one place that
would not survive a reinstall. It belongs beside the library it exercises.
