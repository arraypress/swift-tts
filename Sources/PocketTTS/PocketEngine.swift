//
//  PocketEngine.swift
//  PocketTTS
//
//  PocketTTS (MIT) via FluidAudio — CoreML, runs on iPhone + Mac, with voice
//  cloning. Wraps FluidAudio's `PocketTtsManager` (an actor returning 24 kHz WAV).
//

import Foundation
import SpeechSynthesizer
import FluidAudio

// FluidAudio also exports a `TTSError`; ours is the one we throw.
private typealias TTSError = SpeechSynthesizer.TTSError

/// PocketTTS text-to-speech (CoreML) via FluidAudio, with voice cloning.
public actor PocketEngine: TTSEngine {

    public nonisolated var model: TTSModel { .pocket }

    private let manager: PocketTtsManager
    private var prepared = false

    /// Create a PocketTTS engine (English by default).
    public init(language: PocketTtsLanguage = .english) {
        self.manager = PocketTtsManager(language: language)
    }

    public var isReady: Bool { prepared }

    public func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        do {
            try await manager.initialize()
        } catch {
            throw TTSError.modelDownloadFailed(String(describing: error))
        }
        prepared = true
        onProgress?(1.0)
    }

    public func availableVoices() async throws -> [TTSVoice] {
        [
            TTSVoice(id: PocketTtsConstants.defaultVoice, name: "Default", language: "en-US", model: .pocket)
        ]
    }

    public func synthesize(_ text: String, options: SynthesisOptions) async throws -> SpokenAudio {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TTSError.emptyText }
        guard prepared else { throw TTSError.notPrepared }
        do {
            let wav = try await manager.synthesize(text: text, voice: options.voice?.id)
            return try SpokenAudio(wav: wav)
        } catch let error as TTSError {
            throw error
        } catch {
            throw TTSError.synthesisFailed(String(describing: error))
        }
    }

    /// Clone a voice from a reference audio file, returning a voice descriptor
    /// whose id can be passed via ``SynthesisOptions``. (PocketTTS-specific.)
    public func cloneVoice(from audioURL: URL) async throws -> PocketTtsVoiceData {
        try await manager.cloneVoice(from: audioURL)
    }
}
