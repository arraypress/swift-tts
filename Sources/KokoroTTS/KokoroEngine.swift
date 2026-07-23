//
//  KokoroEngine.swift
//  KokoroTTS
//
//  Kokoro-82M (Apache-2.0) via FluidAudio — CoreML / ANE, runs on iPhone + Mac.
//  The fast, light default. Wraps FluidAudio's `KokoroAneManager` (an actor that
//  downloads weights on first `initialize()` and returns 24 kHz WAV `Data`).
//

import Foundation
import SpeechSynthesizer
import FluidAudio

// FluidAudio also exports a `TTSError`; ours is the one we throw.
private typealias TTSError = SpeechSynthesizer.TTSError

/// Kokoro-82M text-to-speech (CoreML / ANE) via FluidAudio.
public actor KokoroEngine: TTSEngine {

    public nonisolated var model: TTSModel { .kokoro }

    private let manager: KokoroAneManager
    private var prepared = false

    /// Create a Kokoro engine (English variant by default).
    public init() {
        self.manager = KokoroAneManager()
    }

    public var isReady: Bool { prepared }

    public func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        do {
            try await manager.initialize()   // downloads on first run, then loads
        } catch {
            throw TTSError.modelDownloadFailed(String(describing: error))
        }
        prepared = true
        onProgress?(1.0)
    }

    public func availableVoices() async throws -> [TTSVoice] {
        // Kokoro ships fixed voice packs (no cloning). A representative subset.
        [
            TTSVoice(id: "af_heart",  name: "Heart (US, female)", language: "en-US", model: .kokoro),
            TTSVoice(id: "af_bella",  name: "Bella (US, female)", language: "en-US", model: .kokoro),
            TTSVoice(id: "am_adam",   name: "Adam (US, male)",    language: "en-US", model: .kokoro),
            TTSVoice(id: "bf_emma",   name: "Emma (UK, female)",  language: "en-GB", model: .kokoro),
            TTSVoice(id: "bm_george", name: "George (UK, male)",  language: "en-GB", model: .kokoro),
        ]
    }

    public func synthesize(_ text: String, options: SynthesisOptions) async throws -> SpokenAudio {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TTSError.emptyText }
        guard prepared else { throw TTSError.notPrepared }
        do {
            let wav = try await manager.synthesize(
                text: text,
                voice: options.voice?.id,
                speed: Float(options.rate)
            )
            return try SpokenAudio(wav: wav)
        } catch let error as TTSError {
            throw error
        } catch {
            throw TTSError.synthesisFailed(String(describing: error))
        }
    }
}
