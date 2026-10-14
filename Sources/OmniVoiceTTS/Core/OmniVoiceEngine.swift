//
//  OmniVoiceEngine.swift
//  OmniVoiceTTS
//
//  Created by David Sherlock on 2026.
//
//  OmniVoice (k2-fsa) — a diffusion language model over a Qwen3 backbone that
//  writes nine codebooks of Higgs Audio 2 tokens at 24 kHz: 600+ languages,
//  a voice designed from a fixed vocabulary, or one cloned from a clip and its
//  transcript. The network is mlx-audio-swift's port; this engine adds what
//  the port leaves to its caller and the reference does itself — the
//  instruct vocabulary check, language codes, splitting long text with the
//  first piece as the voice for the rest, the reference's audio clean-up, and
//  tag filtering — and refuses to start without its licences being named.
//

import Foundation
import MLX
import MLXAudioTTS
import SpeechSynthesizer

// mlx-audio-swift defines its own TTSError; ours is the one thrown.
private typealias TTSError = SpeechSynthesizer.TTSError

/// OmniVoice text-to-speech on the GPU.
///
/// ```swift
/// let engine = try OmniVoiceEngine(modelDirectory: folder, licence: OmniVoiceLicence.version)
/// try await engine.prepare()
/// var settings = OmniVoiceSettings(voiceDesign: "female, british accent", seed: 7)
/// let (audio, report) = try await engine.synthesize("Good evening.", settings: settings)
/// ```
public actor OmniVoiceEngine: TTSEngine {

    /// Always ``TTSModel/omnivoice``.
    public nonisolated let model: TTSModel = .omnivoice

    /// The folder holding config.json, model.safetensors, the tokenizer and audio_tokenizer/.
    public nonisolated let modelDirectory: URL

    /// MLX's buffer cache is held to this many bytes once the model loads.
    public nonisolated let bufferCacheLimit: Int?

    /// The least memory the engine starts on: 16 GB (it peaks near 4 GB in
    /// bfloat16, 6 GB in float32; measured on a 36 GB Mac, see the README).
    public static let memoryRequirement = MemoryRequirement(gigabytes: 16)

    /// The output sample rate.
    public static let sampleRate = 24_000.0

    /// Samples per codec frame; reference clips are cut to a whole number of them.
    static let hopLength = 960

    /// The precision the speech model runs in (the audio tokenizer always
    /// runs in float32).
    public nonisolated let precision: OmniVoicePrecision

    private var backend: OmniVoiceModel?

    /// - Parameters:
    ///   - modelDirectory: The MLX conversion's folder (mlx-community/OmniVoice).
    ///   - licence: Must be ``OmniVoiceLicence/version``: naming it is accepting it.
    ///   - physicalMemory: The Mac's memory; the real figure unless testing.
    ///   - bufferCacheLimit: A cap on MLX's cache of freed GPU buffers, applied
    ///     on ``prepare(onProgress:)``; nil leaves MLX's own.
    ///   - precision: The speech model's precision. bfloat16 (the default)
    ///     measured 1.5–2× faster than the port's float32 at 32 steps, with a
    ///     peak footprint of 3.7 GB against 5.8 GB, and the same transcripts
    ///     on English, Spanish, French, German, Japanese, Chinese, Arabic and
    ///     clones; the audio tokenizer stays float32 either way.
    /// - Throws: ``OmniVoiceError/licenceNotAccepted(expected:)`` or
    ///   ``OmniVoiceError/insufficientMemory(physicalGB:requiredGB:)``.
    public init(modelDirectory: URL, licence: String,
                physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory,
                bufferCacheLimit: Int? = 256 << 20,
                precision: OmniVoicePrecision = .bfloat16) throws(OmniVoiceError) {
        guard licence == OmniVoiceLicence.version else { throw .licenceNotAccepted(expected: OmniVoiceLicence.version) }
        if let shortfall = Self.memoryRequirement.shortfall(physicalMemory: physicalMemory) {
            throw .insufficientMemory(physicalGB: shortfall.physicalGB, requiredGB: shortfall.requiredGB)
        }
        self.modelDirectory = modelDirectory
        self.bufferCacheLimit = bufferCacheLimit
        self.precision = precision
    }

    public var isReady: Bool { backend != nil }

    /// Whether this model folder can clone (and keep one voice across the
    /// pieces of a long text): the full-precision conversion can, the
    /// bfloat16 one has no semantic encoder.
    public nonisolated var canEncodeReferences: Bool { OmniModelFolder.canEncodeReferences(in: modelDirectory) }

    /// Loads the model (3.3 GB, held as float32). Nothing is downloaded: the
    /// folder must already hold it.
    public func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        guard backend == nil else { return }
        if let bufferCacheLimit { Memory.cacheLimit = bufferCacheLimit }
        let loaded = try await OmniModelFolder.load(modelDirectory)
        if precision == .bfloat16 { OmniModelFolder.convertSpeechModel(loaded, to: .bfloat16) }
        backend = loaded
        onProgress?(1)
    }

    /// OmniVoice has no named voices: it designs one (``OmniVoiceSettings/voiceDesign``)
    /// or clones one (``OmniVoiceSettings/reference``).
    public func availableVoices() async throws -> [TTSVoice] {
        [TTSVoice(id: "default", name: "Default", language: "multilingual", model: .omnivoice)]
    }

    /// Speaks `text` in one piece. ``SynthesisOptions/rate`` is the speed;
    /// ``SynthesisOptions/language`` is used when OmniVoice knows it;
    /// cloning takes ``SynthesisOptions/referenceAudio`` with ``SynthesisOptions/referenceTranscript``.
    public func synthesize(_ text: String, options: SynthesisOptions) async throws -> SpokenAudio {
        var settings = OmniVoiceSettings(language: try? OmniLanguages.resolve(options.language),
                                         speed: options.rate)
        if let audio = options.referenceAudio {
            settings.reference = OmniVoiceReference(audio: audio, transcript: options.referenceTranscript ?? "")
        }
        return try await synthesize(text, settings: settings).audio
    }

    /// Speaks `text`, returning the audio and what it cost.
    public func synthesize(_ text: String, settings: OmniVoiceSettings = OmniVoiceSettings())
        async throws -> (audio: SpokenAudio, report: OmniVoiceReport) {
        var samples: [Float] = []
        let report = try await generate(text, settings: settings) { samples += $0.samples }
        return (SpokenAudio(samples: samples, sampleRate: Self.sampleRate), report)
    }

    /// Speaks `text` as a stream: one element per piece of text as soon as
    /// it is generated, so long text can be played or written while the rest
    /// is made and is never held whole. The last element is empty,
    /// ``OmniVoiceChunk/isFinal``, and carries the report. Cancelling the
    /// consuming task stops generation between diffusion steps.
    public nonisolated func chunks(_ text: String, settings: OmniVoiceSettings = OmniVoiceSettings())
        -> AsyncThrowingStream<OmniVoiceChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let report = try await self.generate(text, settings: settings) { continuation.yield($0) }
                    continuation.yield(OmniVoiceChunk(samples: [], sampleRate: Self.sampleRate,
                                                      index: report.chunks, count: report.chunks, text: "",
                                                      isFinal: true, report: report))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Everything a request will be given, worked out before the model runs:
    /// the filtered text, its pieces, the resolved design and language.
    public static func plan(_ text: String, settings: OmniVoiceSettings) throws(OmniVoiceError) -> OmniVoicePlan {
        let filtered = settings.filtersTags ? OmniTags.filter(text)
            : OmniTags.Filtered(text: text, dropped: [], moved: [])
        let design = try settings.voiceDesign.flatMap { design throws(OmniVoiceError) in
            try VoiceDesignVocabulary.resolve(design, text: filtered.text)
        }
        let language = try settings.language.map { language throws(OmniVoiceError) in
            try OmniLanguages.resolve(language)
        }
        return OmniVoicePlan(pieces: OmniText.chunks(filtered.text, speed: settings.speed), voiceDesign: design,
                             language: language, droppedTags: filtered.dropped, movedTags: filtered.moved)
    }

    private func generate(_ text: String, settings: OmniVoiceSettings,
                          emit: (OmniVoiceChunk) throws -> Void) async throws -> OmniVoiceReport {
        guard let backend else { throw TTSError.notPrepared }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TTSError.emptyText }
        let started = Date()
        let plan = try Self.plan(text, settings: settings)
        guard !plan.pieces.isEmpty else { throw TTSError.emptyText }

        var anchor = try settings.reference.map(prepareReference)
        let anchorsFirstPiece = anchor == nil && settings.keepsVoiceAcrossChunks && plan.pieces.count > 1
            && canEncodeReferences
        var report = OmniVoiceReport(chunks: plan.pieces.count, droppedTags: plan.droppedTags,
                                     movedTags: plan.movedTags, voiceDesign: plan.voiceDesign,
                                     language: plan.language, firstAudioSeconds: nil, peakMemoryBytes: 0)

        for (index, piece) in plan.pieces.enumerated() {
            try Task.checkCancellation()
            // Seeded once, as the reference seeds once: later pieces continue
            // the same random sequence, so a seeded request repeats exactly.
            let parameters = OmniVoiceGenerateParameters(
                numStep: max(1, settings.steps), guidanceScale: Float(settings.guidanceScale),
                speed: Float(settings.speed), postprocessOutput: false, seed: index == 0 ? settings.seed : nil)
            let generated: [Float]
            do {
                let audio = try await backend.generate(
                    text: piece, voice: plan.voiceDesign, refAudio: anchor.map { MLXArray($0.samples) },
                    refText: anchor?.transcript, language: plan.language, ovParameters: parameters)
                generated = audio.asArray(Float.self)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw TTSError.synthesisFailed(String(describing: error))
            }
            Memory.clearCache()
            if index == 0 && anchorsFirstPiece {
                anchor = (Self.wholeFrames(generated), OmniText.punctuated(piece))
            }
            let finished = OmniAudio.finished(generated, sampleRate: Self.sampleRate, isFirst: index == 0)
            if report.firstAudioSeconds == nil { report.firstAudioSeconds = Date().timeIntervalSince(started) }
            try emit(OmniVoiceChunk(samples: finished, sampleRate: Self.sampleRate, index: index,
                                    count: plan.pieces.count, text: piece, isFinal: false, report: nil))
        }
        report.peakMemoryBytes = Memory.peakMemory
        return report
    }

    /// A clone reference the way the reference prepares one: 24 kHz, lifted
    /// if quiet, long pauses cut, a whole number of codec frames, and a
    /// transcript that ends in punctuation.
    private func prepareReference(_ reference: OmniVoiceReference) throws -> (samples: [Float], transcript: String) {
        let transcript = reference.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            throw OmniVoiceError.invalidReference("cloning needs the reference clip's transcript, word for word")
        }
        guard canEncodeReferences else {
            throw OmniVoiceError.invalidReference(
                "this model folder cannot clone: its audio tokenizer has no semantic encoder "
                + "(the bfloat16 conversion strips it; use mlx-community/OmniVoice)")
        }
        guard let audio = reference.audio.resampled(to: Self.sampleRate) else {
            throw OmniVoiceError.invalidReference("cannot convert the reference clip to 24 kHz")
        }
        let prepared = Self.wholeFrames(OmniAudio.preparedReference(audio.samples, sampleRate: Self.sampleRate))
        guard !prepared.isEmpty else { throw OmniVoiceError.invalidReference("the reference clip is silent") }
        return (prepared, OmniText.punctuated(transcript))
    }

    /// `samples` cut to a whole number of codec frames.
    static func wholeFrames(_ samples: [Float]) -> [Float] {
        Array(samples.prefix(samples.count - samples.count % hopLength))
    }
}

/// The precision OmniVoice's speech model runs in.
public enum OmniVoicePrecision: String, Sendable, CaseIterable {
    /// The port's own: every weight held as float32.
    case float32
    /// The Qwen3 backbone and audio embeddings/heads as bfloat16 — the
    /// engine's default: faster, a third less memory, same transcripts.
    case bfloat16
}

/// What a request will send to the model.
public struct OmniVoicePlan: Sendable, Equatable {
    /// The text pieces, generated one at a time.
    public let pieces: [String]
    /// The voice design as the model will get it.
    public let voiceDesign: String?
    /// The language code, or nil to detect it.
    public let language: String?
    /// Cues removed because the model would read them aloud.
    public let droppedTags: [String]
    /// Question tags moved to where they work.
    public let movedTags: [String]
}
