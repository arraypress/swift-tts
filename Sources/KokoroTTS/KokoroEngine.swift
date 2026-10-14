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
    private let phonemizer = KokoroPhonemizer()
    private var prepared = false

    /// Create a Kokoro engine (English variant by default).
    public init() {
        self.manager = KokoroAneManager()
    }

    public var isReady: Bool { prepared }

    /// Every file on disk, loaded or not — see ``KokoroFiles``.
    public var isDownloaded: Bool { KokoroFiles.isDownloaded() }

    /// Downloads what is missing (224 MB on a fresh Mac), reporting
    /// progress, then loads the seven CoreML stages and the US lexicon.
    public func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        do {
            // The model, then the G2P folder with Misaki's lexicons — each a
            // no-op when its files are present. FluidAudio's `initialize()`
            // downloads too, but reports no progress.
            try await KokoroAneResourceDownloader.ensureModels(variant: .english) { progress in
                onProgress?(0.9 * progress.fractionCompleted)
            }
            try await KokoroAneResourceDownloader.ensureG2PAssets { progress in
                onProgress?(0.9 + 0.08 * progress.fractionCompleted)
            }
            try await manager.initialize()
        } catch {
            // A network failure in a sentence ("Could not connect to the
            // server."), not an NSError dump; anything else as it is.
            let failure = error as NSError
            throw TTSError.modelDownloadFailed(
                failure.domain == NSURLErrorDomain ? failure.localizedDescription : String(describing: error))
        }
        try await phonemizer.prepare(british: false)
        prepared = true
        onProgress?(1.0)
    }

    /// `text` as the phonemes Kokoro will be given: normalised (numbers,
    /// dates, money… as words), then read through Misaki's lexicon, with the
    /// neural G2P for words it lacks. Needs the files, not a loaded model.
    ///
    /// - Parameter voice: A voice id; `b…` voices read with the British lexicon.
    public func phonemes(for text: String, voice: String? = nil, language: String = "en-US") async throws -> String {
        let british = Self.isBritish(voice)
        let spoken = SpokenText.normalize(text, language: british ? "en-GB" : language)
        return try await phonemizer.phonemes(spoken, british: british)
    }

    /// Misaki reads British voices (`bf_…`, `bm_…`) with its British lexicon.
    static func isBritish(_ voice: String?) -> Bool {
        (voice ?? KokoroVoices.defaultID).hasPrefix("b")
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

        // Numbers, dates, money and abbreviations become words first; long
        // text is then cut into pieces the model can take (see KokoroText)
        // and the audio joined.
        let british = Self.isBritish(options.voice?.id)
        let spoken = SpokenText.normalize(text, language: british ? "en-GB" : options.language)
        let pieces = KokoroText.pieces(spoken)
        var samples: [Float] = []
        var sampleRate = 24_000.0
        for piece in pieces {
            let audio = try await speak(piece, voice: options.voice?.id, british: british, speed: Float(options.rate))
            guard !audio.isEmpty else { continue }
            if !samples.isEmpty { samples += KokoroText.gap(sampleRate: audio.sampleRate) }
            samples += audio.samples
            sampleRate = audio.sampleRate
        }
        return SpokenAudio(samples: samples, sampleRate: sampleRate)
    }

    /// One piece; if the model still finds it too long, its halves.
    private func speak(_ piece: String, voice: String?, british: Bool, speed: Float) async throws -> SpokenAudio {
        do {
            // Kokoro's own front end (Misaki) instead of FluidAudio's neural
            // G2P, which says "ice" for "is". Punctuation stays in, so the
            // model pauses and lifts a question the way it was trained to.
            let phonemes = try await phonemizer.phonemes(piece, british: british)
            guard !phonemes.trimmingCharacters(in: .whitespaces).isEmpty else {
                return SpokenAudio(samples: [], sampleRate: 24_000)
            }
            let result = try await manager.synthesizeFromPhonemesDetailed(phonemes, voice: voice, speed: speed)
            return SpokenAudio(samples: result.samples, sampleRate: Double(result.sampleRate))
        } catch let error as KokoroAneError {
            switch error {
            case .phonemeSequenceTooLong, .acousticFramesExceedCap:
                guard let (first, second) = KokoroText.halves(piece) else {
                    throw TTSError.synthesisFailed("Kokoro cannot say “\(piece.prefix(40))” in one pass: \(error)")
                }
                let head = try await speak(first, voice: voice, british: british, speed: speed)
                let tail = try await speak(second, voice: voice, british: british, speed: speed)
                return SpokenAudio(samples: head.samples + KokoroText.gap(sampleRate: head.sampleRate) + tail.samples,
                                   sampleRate: head.sampleRate)
            default:
                throw TTSError.synthesisFailed(String(describing: error))
            }
        } catch let error as TTSError {
            throw error
        } catch {
            throw TTSError.synthesisFailed(String(describing: error))
        }
    }

    /// Speaks IPA directly, skipping the grapheme-to-phoneme step.
    ///
    /// The reason to want this is ``KokoroPhonemes``: the G2P in front of this
    /// model is the part that gets words wrong, and everything behind it is
    /// sound. Supplying phonemes yourself is how you pronounce a name, a
    /// loanword, or one of the words this G2P simply fails.
    ///
    /// The string is checked against the model's vocabulary first, because the
    /// encoder drops what it does not recognise without saying so.
    public func synthesize(
        phonemes: String, options: SynthesisOptions
    ) async throws -> SpokenAudio {
        guard prepared else { throw TTSError.notPrepared }
        try KokoroPhonemes.validate(phonemes)

        if let voice = options.voice?.id, voice != "af_heart" {
            try await KokoroVoicePacks.ensure(voice, in: KokoroVoicePacks.cacheDirectory)
        }

        do {
            let wav = try await manager.synthesizeFromPhonemes(
                phonemes.trimmingCharacters(in: .whitespacesAndNewlines),
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
