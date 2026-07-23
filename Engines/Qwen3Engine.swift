//
//  Qwen3Engine.swift  —  reference adapter (MLX / GPU, Mac-class)
//  SpeechSynthesizer
//
//  Wraps Qwen3-TTS (via mlx-audio-swift) behind `TTSEngine`. Qwen3-TTS is
//  Apache-2.0, multilingual (incl. Japanese), long-form, with voice cloning.
//  MLX/GPU → Mac-class.
//
//  ⚠️  READY-TO-WIRE REFERENCE (not compiled as shipped). Same wiring as
//      ChatterboxEngine — declare a `Qwen3TTS` target on mlx-audio-swift and
//      verify the model type + generate signature against your version.
//

import Foundation
import SpeechSynthesizer
import MLXAudioTTS

/// Qwen3-TTS text-to-speech via MLX (GPU), multilingual.
public actor Qwen3Engine: TTSEngine {

    public nonisolated var model: TTSModel { .qwen3 }

    private var backend: Qwen3TTSModel?

    public var isReady: Bool { backend != nil }

    /// The Hugging Face repo id for the MLX-converted weights.
    public let repoID: String

    public init(repoID: String = "mlx-community/Qwen3-TTS") {
        self.repoID = repoID
    }

    public func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        do {
            backend = try await Qwen3TTSModel.fromPretrained(repoID)
        } catch {
            throw TTSError.modelDownloadFailed(String(describing: error))
        }
        onProgress?(1.0)
    }

    public func availableVoices() async throws -> [TTSVoice] {
        // Qwen3-TTS is multilingual — surface a per-language voice list here.
        [
            TTSVoice(id: "default-en", name: "Default (English)",  language: "en-US", model: .qwen3),
            TTSVoice(id: "default-ja", name: "Default (Japanese)", language: "ja-JP", model: .qwen3),
        ]
    }

    public func synthesize(_ text: String, options: SynthesisOptions) async throws -> SpokenAudio {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TTSError.emptyText }
        guard let backend else { throw TTSError.notPrepared }

        do {
            let result = try await backend.generate(text: text, language: options.language, parameters: .init())
            return SpokenAudio(samples: result.audio, sampleRate: result.sampleRate)
        } catch {
            throw TTSError.synthesisFailed(String(describing: error))
        }
    }
}
