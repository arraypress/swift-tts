//
//  MLXEngine.swift
//  MLXTTS
//
//  MLX/GPU text-to-speech via mlx-audio-swift — the Mac-class tier. One engine
//  serves both Chatterbox (MIT, best-sounding) and Qwen3-TTS (Apache,
//  multilingual), since mlx-audio-swift exposes them behind a common
//  `SpeechGenerationModel` protocol loaded by `TTS.loadModel(modelRepo:)`.
//

import Foundation
import SpeechSynthesizer
import MLX
import MLXAudioTTS

// mlx-audio-swift also defines TTS-related error types; ours is what we throw.
private typealias TTSError = SpeechSynthesizer.TTSError

/// MLX/GPU text-to-speech (Chatterbox, Qwen3-TTS, …) via mlx-audio-swift.
///
/// A `final class` (not an actor) because mlx-audio-swift's `SpeechGenerationModel`
/// is a non-Sendable class existential; `@unchecked Sendable` documents that
/// callers prepare-then-synthesize rather than racing the two.
public final class MLXEngine: TTSEngine, @unchecked Sendable {

    public let model: TTSModel

    /// The Hugging Face repo id for the MLX-converted weights.
    public let repoID: String

    private var backend: SpeechGenerationModel?

    /// Create an MLX engine for a model at `repoID`.
    public init(model: TTSModel, repoID: String) {
        self.model = model
        self.repoID = repoID
    }

    /// Chatterbox (MIT) — best-sounding, emotion + voice cloning.
    public static func chatterbox(repoID: String = "mlx-community/Chatterbox-TTS-fp16") -> MLXEngine {
        MLXEngine(model: .chatterbox, repoID: repoID)
    }

    /// Qwen3-TTS (Apache-2.0) — multilingual, long-form.
    public static func qwen3(repoID: String = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit") -> MLXEngine {
        MLXEngine(model: .qwen3, repoID: repoID)
    }

    public var isReady: Bool { backend != nil }

    public func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        do {
            backend = try await TTS.loadModel(modelRepo: repoID)   // downloads MLX weights on first run
        } catch {
            throw TTSError.modelDownloadFailed(String(describing: error))
        }
        onProgress?(1.0)
    }

    public func availableVoices() async throws -> [TTSVoice] {
        [TTSVoice(id: "default", name: "Default", language: "en-US", model: model)]
    }

    public func synthesize(_ text: String, options: SynthesisOptions) async throws -> SpokenAudio {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TTSError.emptyText }
        guard let backend else { throw TTSError.notPrepared }
        do {
            let audio = try await backend.generate(
                text: text,
                voice: options.voice?.id,
                refAudio: nil,
                refText: nil,
                language: options.language,
                generationParameters: backend.defaultGenerationParameters
            )
            // mlx-audio returns a 1-D MLXArray of float samples.
            let samples = audio.asArray(Float.self)
            return SpokenAudio(samples: samples, sampleRate: Double(backend.sampleRate))
        } catch let error as TTSError {
            throw error
        } catch {
            throw TTSError.synthesisFailed(String(describing: error))
        }
    }
}
