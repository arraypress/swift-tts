//
//  SupertonicEngine.swift
//  SupertonicTTS
//
//  Supertonic 3 (OpenRAIL-M) via ONNX Runtime — 31 languages in ~99M parameters,
//  light enough for a phone. Four graphs in sequence: duration prediction, text
//  encoding, a flow-matching denoise loop, then a vocoder.
//

import Foundation
import OnnxRuntimeBindings
import SpeechSynthesizer

private typealias TTSError = SpeechSynthesizer.TTSError

/// Supertonic 3 text-to-speech via ONNX Runtime.
///
/// ```swift
/// let engine = SupertonicEngine()
/// try await engine.prepare()
/// let audio = try await engine.synthesize("Hello there.")
/// ```
public actor SupertonicEngine: TTSEngine {

    public nonisolated var model: TTSModel { .supertonic }

    /// Denoising steps in the flow-matching loop.
    ///
    /// Four, measured rather than guessed. Quality was checked by synthesizing a sentence and
    /// running the result back through Apple's speech recogniser:
    ///
    /// | steps | speed | recognised as |
    /// |-------|-------|---------------|
    /// | 2     | 20.0x | "Separation. **It was** evaluated…" — word dropped |
    /// | 4     | 11.6x | "Separation **pipeline** was evaluated…" — correct |
    /// | 8     | 6.1x  | correct |
    /// | 16    | 3.2x  | correct |
    ///
    /// Two steps is visibly cheaper and drops words; beyond four the cost doubles for no
    /// measurable gain in intelligibility.
    public static let defaultSteps = 4

    private let modelDirectory: URL
    private let steps: Int

    private var sessions: Sessions?
    private var config: Config?
    private var indexer: [Int64] = []

    /// - Parameters:
    ///   - modelDirectory: Where the `onnx/` and `voice_styles/` folders live. Defaults to the
    ///     cache in Application Support, which ``prepare(onProgress:)`` fills on first use.
    ///   - steps: Denoising steps. See ``defaultSteps``.
    public init(
        modelDirectory: URL = SupertonicAssetStore.defaultDirectory,
        steps: Int = SupertonicEngine.defaultSteps
    ) {
        self.modelDirectory = modelDirectory
        self.steps = max(1, steps)
    }

    /// Download size, if the assets are not already present. `0` when they are.
    ///
    /// Worth asking about before spending ~400 MB of someone's connection unannounced.
    public nonisolated var pendingDownloadBytes: Int64 {
        SupertonicAssetStore.isInstalled(at: modelDirectory) ? 0 : SupertonicAssetStore.downloadBytes
    }

    public var isReady: Bool { sessions != nil }

    public func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        guard sessions == nil else { onProgress?(1.0); return }

        // Download dominates a first run and session creation is ~0.3 s, so the bar is given
        // over to the download almost entirely rather than split evenly between two phases of
        // wildly different length.
        try await SupertonicAssetStore.install(at: modelDirectory) { fraction in
            onProgress?(fraction * 0.98)
        }

        let onnx = modelDirectory.appendingPathComponent("onnx")
        do {
            // The CPU provider, deliberately, and not an oversight.
            //
            // ONNX Runtime's CoreML provider supports only part of these graphs — it split the
            // vector estimator into ~134 partitions covering 702 of 1032 nodes — so the run
            // spends its time crossing between CoreML and CPU rather than computing. Measured:
            // 11.6x real time on CPU against 5.9x on CoreML, plus 6.5 s of session setup
            // against 0.3 s.
            let env = try ORTEnv(loggingLevel: .warning)
            let options = try ORTSessionOptions()
            try options.setGraphOptimizationLevel(.all)

            func session(_ name: String) throws -> ORTSession {
                try ORTSession(
                    env: env,
                    modelPath: onnx.appendingPathComponent("\(name).onnx").path,
                    sessionOptions: options
                )
            }

            let config = try Config(contentsOf: onnx.appendingPathComponent("tts.json"))
            let indexerData = try Data(contentsOf: onnx.appendingPathComponent("unicode_indexer.json"))

            self.config = config
            self.indexer = try JSONDecoder().decode([Int64].self, from: indexerData)
            self.sessions = Sessions(
                durationPredictor: try session("duration_predictor"),
                textEncoder: try session("text_encoder"),
                vectorEstimator: try session("vector_estimator"),
                vocoder: try session("vocoder")
            )
        } catch {
            throw TTSError.modelDownloadFailed(String(describing: error))
        }
        onProgress?(1.0)
    }

    public func availableVoices() async throws -> [TTSVoice] {
        let directory = modelDirectory.appendingPathComponent("voice_styles")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files
            .filter { $0.hasSuffix(".json") }
            .sorted()
            .map { file in
                let id = String(file.dropLast(5))
                return TTSVoice(
                    id: id,
                    name: "\(id.hasPrefix("F") ? "Female" : "Male") \(id.dropFirst())",
                    language: "multi",
                    model: .supertonic
                )
            }
    }

    public func synthesize(_ text: String, options: SynthesisOptions) async throws -> SpokenAudio {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TTSError.emptyText }
        guard let sessions, let config else { throw TTSError.notPrepared }

        do {
            let style = try VoiceStyle(
                contentsOf: modelDirectory
                    .appendingPathComponent("voice_styles")
                    .appendingPathComponent("\(options.voice?.id ?? "F1").json")
            )
            let pipeline = SupertonicPipeline(
                sessions: sessions,
                config: config,
                indexer: indexer,
                steps: steps
            )
            let samples = try pipeline.synthesize(text: text, style: style, speed: Float(options.rate))
            // 44.1 kHz, unlike the 24 kHz the CoreML engines produce — Supertonic's
            // autoencoder is trained at the higher rate, so it is passed through rather than
            // resampled down to match.
            return SpokenAudio(samples: samples, sampleRate: Double(config.ae.sampleRate))
        } catch let error as TTSError {
            throw error
        } catch {
            throw TTSError.synthesisFailed(String(describing: error))
        }
    }
}

// MARK: - Sessions

/// The four graphs, held together so `isReady` is a single check.
struct Sessions {
    let durationPredictor: ORTSession
    let textEncoder: ORTSession
    let vectorEstimator: ORTSession
    let vocoder: ORTSession
}
