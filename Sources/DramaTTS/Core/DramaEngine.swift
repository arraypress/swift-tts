//
//  DramaEngine.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  Fish Audio Drama 3 — expressive multi-speaker speech with inline delivery
//  cues ([whispers], [angry], [laughs], {feeling stressed}), speaker turns
//  (<|speaker:1|>) and voice cloning from a clip and its transcript, on MLX.
//  A 35B-parameter mixture-of-experts backbone (3B active) with a codebook
//  tower and Fish's 44.1 kHz DAC codec; the 4-bit checkpoint is 22 GB.
//
//  Opt-in twice over: the engine will not start unless it is handed
//  ``DramaLicence/version`` — the Fish Audio Community License is not an open
//  licence — and it refuses Macs with less than 36 GB of memory (32 GB for a
//  lite folder made by ``DramaLiteConversion``).
//

import Foundation
import MLX
import SpeechSynthesizer

/// Drama 3 text-to-speech on the GPU.
///
/// ```swift
/// let engine = try DramaEngine(modelDirectory: folder, licence: DramaLicence.version)
/// try await engine.prepare()
/// let audio = try await engine.synthesize("[whispering] Don't tell anyone.")
/// ```
public actor DramaEngine: TTSEngine {

    /// Always ``TTSModel/drama``.
    public nonisolated let model: TTSModel = .drama

    /// The folder holding config.json, the model shards, codec.safetensors and the tokenizer.
    public nonisolated let modelDirectory: URL

    /// MLX's buffer cache is held to this many bytes once the model loads.
    public nonisolated let bufferCacheLimit: Int?

    private var pipeline: DramaPipeline?

    /// - Parameters:
    ///   - modelDirectory: The converted model's folder.
    ///   - licence: Must be ``DramaLicence/version``: naming it is accepting it.
    ///   - physicalMemory: The Mac's memory; the real figure unless testing.
    ///   - bufferCacheLimit: A cap on MLX's process-wide cache of freed GPU
    ///     buffers, applied on ``prepare(onProgress:)``; nil leaves MLX's own.
    ///     Measured: 256 MB took the process's peak footprint from 29.2 to
    ///     25.8 GB with no loss of speed.
    /// - Throws: ``DramaError/licenceNotAccepted(expected:)`` or
    ///   ``DramaError/insufficientMemory(physicalGB:requiredGB:)``.
    public init(modelDirectory: URL, licence: String,
                physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory,
                bufferCacheLimit: Int? = 256 << 20) throws(DramaError) {
        guard licence == DramaLicence.version else { throw .licenceNotAccepted(expected: DramaLicence.version) }
        let lite = DramaLiteStamp.read(modelDirectory) != nil
        if let problem = MemoryFloor.problem(physicalMemory: physicalMemory, lite: lite) { throw problem }
        self.modelDirectory = modelDirectory
        self.bufferCacheLimit = bufferCacheLimit
    }

    /// The least memory the engine starts on, in bytes.
    public static var minimumMemory: UInt64 { MemoryFloor.minimumBytes }

    /// The least memory the engine starts on with the full or the lite folder, in bytes.
    public static func minimumMemory(lite: Bool) -> UInt64 { MemoryFloor.requirement(lite: lite).minimumBytes }

    public var isReady: Bool { pipeline != nil }

    /// Loads the model (about 22 GB into memory). Nothing is downloaded here:
    /// the folder must already hold the model.
    public func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        guard pipeline == nil else { return }
        if let bufferCacheLimit { Memory.cacheLimit = bufferCacheLimit }
        pipeline = try await DramaPipeline(folder: modelDirectory)
        onProgress?(1)
    }

    /// Drama 3 has no named voices: speakers are `<|speaker:0|>`…`<|speaker:15|>`
    /// in the text, and a voice of your own comes from a reference clip.
    public func availableVoices() async throws -> [TTSVoice] {
        [TTSVoice(id: "default", name: "Default", language: "multilingual", model: .drama)]
    }

    /// Speaks `text` in one piece. Cloning uses ``SynthesisOptions/referenceAudio``
    /// with ``SynthesisOptions/referenceTranscript``.
    public func synthesize(_ text: String, options: SynthesisOptions) async throws -> SpokenAudio {
        var references: [DramaReference] = []
        if let audio = options.referenceAudio {
            guard let transcript = options.referenceTranscript,
                  !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DramaError.invalidReference("cloning needs the reference clip's transcript")
            }
            references = [DramaReference(audio: audio, transcript: transcript)]
        }
        return try await synthesize(text, references: references, settings: DramaSettings()).audio
    }

    /// Speaks `text`, returning the audio and what it cost.
    public func synthesize(_ text: String, references: [DramaReference] = [],
                           settings: DramaSettings = DramaSettings()) async throws -> (audio: SpokenAudio,
                                                                                         report: DramaReport) {
        var samples: [Float] = []
        var rate = 44_100.0
        let report = try generate(text, references: references, settings: settings) { chunk in
            samples += chunk.samples
            rate = chunk.sampleRate
        }
        return (SpokenAudio(samples: samples, sampleRate: rate), report)
    }

    /// Speaks `text` as a stream of pieces, each ready as soon as it is
    /// decoded (about every 0.74 s of audio), for playback while the rest is
    /// generated. The last piece is empty, ``DramaChunk/isFinal``, and carries
    /// the ``DramaChunk/report``. Cancelling the consuming task stops generation.
    public nonisolated func chunks(_ text: String, references: [DramaReference] = [],
                                   settings: DramaSettings = DramaSettings()) -> AsyncThrowingStream<DramaChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let report = try await self.generate(text, references: references, settings: settings) {
                        continuation.yield($0)
                    }
                    continuation.yield(DramaChunk(samples: [], sampleRate: 44_100, segment: report.chunks - 1,
                                                  isFinal: true, report: report))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func generate(_ text: String, references: [DramaReference], settings: DramaSettings,
                          emit: (DramaChunk) throws -> Void) throws -> DramaReport {
        guard let pipeline else { throw TTSError.notPrepared }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TTSError.emptyText }
        return try pipeline.generate(text, references: references, settings: settings,
                                     isCancelled: { Task.isCancelled }, emit: emit)
    }
}
