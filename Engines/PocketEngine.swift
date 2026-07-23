//
//  PocketEngine.swift  —  reference adapter (CoreML, mobile-friendly, cloning)
//  SpeechSynthesizer
//
//  Wraps FluidAudio's PocketTTS backend behind `TTSEngine`. PocketTTS is MIT,
//  ~100M params, streaming-capable, and clones a voice from a reference sample.
//  Runs on iPhone and Mac.
//
//  ⚠️  READY-TO-WIRE REFERENCE (not compiled as shipped). Same wiring as
//      KokoroEngine — declare a `PocketTTS` target on FluidAudio and verify the
//      manager's API against your resolved version.
//

import Foundation
import SpeechSynthesizer
import FluidAudio

/// PocketTTS text-to-speech via FluidAudio (CoreML), with voice cloning.
public actor PocketEngine: TTSEngine {

    public nonisolated var model: TTSModel { .pocket }

    // Documented entry point: `PocketTtsManager(language:)`.
    private var manager: PocketTtsManager?

    public var isReady: Bool { manager != nil }

    public init() {}

    public func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        let manager = PocketTtsManager(language: .english)   // pick from the language packs
        do {
            try await manager.initialize()
        } catch {
            throw TTSError.modelDownloadFailed(String(describing: error))
        }
        self.manager = manager
        onProgress?(1.0)
    }

    public func availableVoices() async throws -> [TTSVoice] {
        // PocketTTS is primarily cloning-driven; expose its stock voices here and
        // add a `clone(from:)` path (below) for reference audio.
        [
            TTSVoice(id: "default", name: "Default", language: "en-US", model: .pocket)
        ]
    }

    public func synthesize(_ text: String, options: SynthesisOptions) async throws -> SpokenAudio {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TTSError.emptyText }
        guard let manager else { throw TTSError.notPrepared }

        do {
            // FluidAudio's PocketTTS returns encoded audio Data (24 kHz mono WAV).
            // Decode to Float samples for our common `SpokenAudio` type.
            let audioData = try await manager.synthesize(text: text)
            return try Self.decodeWAV(audioData)
        } catch let error as TTSError {
            throw error
        } catch {
            throw TTSError.synthesisFailed(String(describing: error))
        }
    }

    /// Decode a 16-bit PCM WAV blob into `SpokenAudio` (inverse of `wavData()`).
    static func decodeWAV(_ data: Data) throws -> SpokenAudio {
        // Minimal parse: sample rate at offset 24, PCM data after the 44-byte header.
        guard data.count > 44 else { throw TTSError.synthesisFailed("short WAV") }
        let sampleRate = data[24..<28].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let pcm = data[44...]
        var samples = [Float]()
        samples.reserveCapacity(pcm.count / 2)
        var index = pcm.startIndex
        while index + 1 < pcm.endIndex {
            let lo = UInt16(pcm[index]); let hi = UInt16(pcm[index + 1])
            let value = Int16(bitPattern: lo | (hi << 8))
            samples.append(Float(value) / Float(Int16.max))
            index += 2
        }
        return SpokenAudio(samples: samples, sampleRate: Double(sampleRate))
    }
}
