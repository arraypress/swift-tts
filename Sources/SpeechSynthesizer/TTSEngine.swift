//
//  TTSEngine.swift
//  SpeechSynthesizer
//
//  The protocol every backend implements. Callers program against this, so a
//  Kokoro (CoreML) engine and a Chatterbox (MLX) engine are interchangeable —
//  the same way the transcriber's engines all return `Transcript`.
//

import Foundation

/// A text-to-speech engine backed by one ``TTSModel``.
public protocol TTSEngine: Sendable {

    /// The model this engine runs.
    var model: TTSModel { get }

    /// Whether the model's weights are downloaded and loaded, ready to synthesize.
    var isReady: Bool { get async }

    /// Download (if needed) and load the model. Call once before synthesizing.
    ///
    /// The first call for a given model downloads its weights; subsequent runs
    /// load from disk and are fully offline.
    ///
    /// - Parameter onProgress: Optional download/load progress in `0...1`.
    func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws

    /// The voices this engine offers (once prepared).
    func availableVoices() async throws -> [TTSVoice]

    /// Synthesize `text` into ``SpokenAudio``.
    func synthesize(_ text: String, options: SynthesisOptions) async throws -> SpokenAudio
}

public extension TTSEngine {

    /// Prepare with no progress callback.
    func prepare() async throws {
        try await prepare(onProgress: nil)
    }

    /// Synthesize with default options.
    func synthesize(_ text: String) async throws -> SpokenAudio {
        try await synthesize(text, options: SynthesisOptions())
    }
}
