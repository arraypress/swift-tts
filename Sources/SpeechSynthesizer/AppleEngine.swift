//
//  AppleEngine.swift
//  SpeechSynthesizer
//
//  The batteries-included engine: Apple's built-in `AVSpeechSynthesizer`. No
//  model download, no external dependency, available on every device — the ideal
//  default and fallback. Renders to `SpokenAudio` (not just plays aloud) via the
//  synthesizer's buffer-callback API.
//

import Foundation
import AVFoundation

/// Text-to-speech using Apple's built-in system voices.
public actor AppleEngine: TTSEngine {

    public nonisolated var model: TTSModel { .apple }

    /// Always ready — nothing to download.
    public var isReady: Bool { true }

    public init() {}

    /// No-op: system voices need no download. Reports complete immediately.
    public func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        onProgress?(1.0)
    }

    public func availableVoices() async throws -> [TTSVoice] {
        AVSpeechSynthesisVoice.speechVoices().map { voice in
            TTSVoice(id: voice.identifier, name: voice.name, language: voice.language, model: .apple)
        }
    }

    public func synthesize(_ text: String, options: SynthesisOptions) async throws -> SpokenAudio {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TTSError.emptyText }
        return try await Self.render(text: text, options: options)
    }

    // MARK: - Rendering

    /// Holds the synthesizer + accumulating samples across the escaping callback.
    /// `@unchecked Sendable`: the buffer callback is invoked serially, so the
    /// mutations below never race.
    private final class Session: @unchecked Sendable {
        let synthesizer = AVSpeechSynthesizer()
        var samples: [Float] = []
        var sampleRate: Double
        var finished = false
        init(sampleRate: Double) { self.sampleRate = sampleRate }
    }

    private static func render(text: String, options: SynthesisOptions) async throws -> SpokenAudio {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SpokenAudio, Error>) in
            let session = Session(sampleRate: options.sampleRate)

            let utterance = AVSpeechUtterance(string: text)
            if let voiceID = options.voice?.id, let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
                utterance.voice = voice
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: options.language)
            }
            // Map our 1.0-is-normal multiplier onto AVSpeech's rate scale.
            let scaled = AVSpeechUtteranceDefaultSpeechRate * Float(options.rate)
            utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, scaled))

            session.synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }

                // A zero-length buffer signals the end of the utterance.
                if pcm.frameLength == 0 {
                    if !session.finished {
                        session.finished = true
                        continuation.resume(returning: SpokenAudio(samples: session.samples, sampleRate: session.sampleRate))
                    }
                    return
                }

                session.sampleRate = pcm.format.sampleRate
                let count = Int(pcm.frameLength)
                if let float = pcm.floatChannelData {
                    session.samples.append(contentsOf: UnsafeBufferPointer(start: float[0], count: count))
                } else if let int16 = pcm.int16ChannelData {
                    let channel = int16[0]
                    for index in 0..<count {
                        session.samples.append(Float(channel[index]) / Float(Int16.max))
                    }
                }
            }
        }
    }
}
