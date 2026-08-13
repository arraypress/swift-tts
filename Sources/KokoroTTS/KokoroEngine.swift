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

    /// Every English voice Kokoro-82M was trained with.
    ///
    /// All of them work. The list used to be five, four of which answered a
    /// 404 at synthesis — the converted model repository ships only
    /// `af_heart`, and the rest are fetched from the original on first use.
    /// See ``KokoroVoicePacks``.
    public func availableVoices() async throws -> [TTSVoice] {
        KokoroVoices.voices()
    }

    public func synthesize(_ text: String, options: SynthesisOptions) async throws -> SpokenAudio {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TTSError.emptyText }
        guard prepared else { throw TTSError.notPrepared }

        // The pack has to be on disk before the engine reaches for it. Only
        // `af_heart` ships with the converted model; anything else is fetched
        // once and cached. Doing it here rather than in prepare() means a run
        // downloads the one voice it asked for, not fifty-four.
        if let voice = options.voice?.id, voice != "af_heart" {
            try await KokoroVoicePacks.ensure(voice, in: KokoroVoicePacks.cacheDirectory)
        }

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
