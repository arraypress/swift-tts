//
//  ChatterboxEngine.swift  —  reference adapter (MLX / GPU, Mac-class)
//  SpeechSynthesizer
//
//  Wraps Chatterbox (via mlx-audio-swift) behind `TTSEngine`. Chatterbox is MIT,
//  the best-sounding commercial-safe model, with emotion control and 10-second
//  voice cloning. MLX/GPU → Mac-class (heavy for phones).
//
//  ⚠️  READY-TO-WIRE REFERENCE (not compiled as shipped). To use it:
//        1. Add mlx-audio-swift (https://github.com/Blaizzy/mlx-audio-swift) to
//           Package.swift dependencies.
//        2. Declare a `ChatterboxTTS` target depending on
//           ["SpeechSynthesizer", .product(name: "MLXAudioTTS", package: "mlx-audio-swift")]
//           and move this file to Sources/ChatterboxTTS/.
//        3. Verify the model type + generate signature against your version —
//           mlx-audio-swift's documented pattern is `Model.fromPretrained(_:)`
//           then `generate(text:parameters:)`.
//

import Foundation
import SpeechSynthesizer
import MLXAudioTTS

/// Chatterbox text-to-speech via MLX (GPU).
public actor ChatterboxEngine: TTSEngine {

    public nonisolated var model: TTSModel { .chatterbox }

    private var backend: ChatterboxModel?

    public var isReady: Bool { backend != nil }

    /// The Hugging Face repo id for the MLX-converted weights.
    public let repoID: String

    public init(repoID: String = "mlx-community/chatterbox") {
        self.repoID = repoID
    }

    public func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        do {
            // Downloads the MLX weights on first run.
            backend = try await ChatterboxModel.fromPretrained(repoID)
        } catch {
            throw TTSError.modelDownloadFailed(String(describing: error))
        }
        onProgress?(1.0)
    }

    public func availableVoices() async throws -> [TTSVoice] {
        [
            TTSVoice(id: "default", name: "Default", language: "en-US", model: .chatterbox)
        ]
    }

    public func synthesize(_ text: String, options: SynthesisOptions) async throws -> SpokenAudio {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TTSError.emptyText }
        guard let backend else { throw TTSError.notPrepared }

        do {
            // Returns Float samples; confirm the sample rate your build emits.
            let result = try await backend.generate(text: text, parameters: .init())
            return SpokenAudio(samples: result.audio, sampleRate: result.sampleRate)
        } catch {
            throw TTSError.synthesisFailed(String(describing: error))
        }
    }
}
