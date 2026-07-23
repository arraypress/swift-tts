//
//  KokoroEngine.swift  —  reference adapter (CoreML / ANE, mobile-friendly)
//  SpeechSynthesizer
//
//  Wraps FluidAudio's Kokoro-82M backend behind `TTSEngine`. Kokoro is the
//  default: Apache-2.0, ~24 kHz, runs on iPhone and Mac via the Neural Engine.
//
//  ⚠️  READY-TO-WIRE REFERENCE. This file is NOT compiled by the package as
//      shipped (it would pull the FluidAudio dependency). To use it:
//        1. Add FluidAudio to Package.swift dependencies.
//        2. Declare a `KokoroTTS` target that depends on
//           ["SpeechSynthesizer", .product(name: "FluidAudio", package: "FluidAudio")]
//           and move this file to Sources/KokoroTTS/.
//        3. Build on macOS 26 and verify the FluidAudio API names/signatures
//           against your resolved version (see notes inline).
//

import Foundation
import SpeechSynthesizer
import FluidAudio

/// Kokoro-82M text-to-speech via FluidAudio (CoreML / ANE).
public actor KokoroEngine: TTSEngine {

    public nonisolated var model: TTSModel { .kokoro }

    // FluidAudio's Kokoro manager. Verify the exact type name in your version;
    // the documented entry point is `KokoroAneManager`.
    private var manager: KokoroAneManager?

    public var isReady: Bool { manager != nil }

    public init() {}

    public func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        let manager = KokoroAneManager()
        do {
            try await manager.initialize()          // downloads weights on first run, then loads
        } catch {
            throw TTSError.modelDownloadFailed(String(describing: error))
        }
        self.manager = manager
        onProgress?(1.0)
    }

    public func availableVoices() async throws -> [TTSVoice] {
        // Kokoro ships fixed voice packs (no cloning). A representative subset —
        // extend with the full `af_/am_/bf_/…` catalog for your locales.
        [
            TTSVoice(id: "af_heart",  name: "Heart (US, female)",   language: "en-US", model: .kokoro),
            TTSVoice(id: "af_bella",  name: "Bella (US, female)",   language: "en-US", model: .kokoro),
            TTSVoice(id: "am_adam",   name: "Adam (US, male)",      language: "en-US", model: .kokoro),
            TTSVoice(id: "bf_emma",   name: "Emma (UK, female)",    language: "en-GB", model: .kokoro),
            TTSVoice(id: "bm_george", name: "George (UK, male)",    language: "en-GB", model: .kokoro),
        ]
    }

    public func synthesize(_ text: String, options: SynthesisOptions) async throws -> SpokenAudio {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TTSError.emptyText }
        guard let manager else { throw TTSError.notPrepared }

        do {
            // Documented FluidAudio call returns mono Float samples at 24 kHz.
            // Pass the voice id / rate through if your version exposes them.
            let samples = try await manager.synthesize(text: text)
            return SpokenAudio(samples: samples, sampleRate: 24_000)
        } catch {
            throw TTSError.synthesisFailed(String(describing: error))
        }
    }
}
