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

    /// Holds the synthesizer, the accumulating samples and the continuation
    /// across the escaping callbacks, and is the synthesizer's delegate.
    ///
    /// The end of the utterance is the delegate's `didFinish`, **not** the
    /// first empty buffer. `write(_:toBufferCallback:)` hands back a
    /// zero-length buffer at the end of every stretch it synthesises, and a
    /// paragraph is several stretches: measured on a 144-word paragraph, four
    /// empty buffers arrived (after 12.4 s, 22.9 s, 32.6 s and 40.1 s of
    /// audio) and `didFinish` came straight after the last. Stopping at the
    /// first one returned only the opening 12 seconds.
    ///
    /// `@unchecked Sendable`: every field is guarded by `lock`. Both callbacks
    /// arrive on the main queue, in order, so the buffers are all in before
    /// `didFinish` runs.
    private final class Session: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
        let synthesizer = AVSpeechSynthesizer()
        private let lock = NSLock()
        private var samples: [Float] = []
        private var sampleRate: Double
        private var continuation: CheckedContinuation<SpokenAudio, Error>?

        init(sampleRate: Double, continuation: CheckedContinuation<SpokenAudio, Error>) {
            self.sampleRate = sampleRate
            self.continuation = continuation
            super.init()
            synthesizer.delegate = self
        }

        /// Appends one buffer; empty ones are boundaries, not the end.
        func append(_ pcm: AVAudioPCMBuffer) {
            let count = Int(pcm.frameLength)
            guard count > 0 else { return }
            lock.lock()
            defer { lock.unlock() }
            sampleRate = pcm.format.sampleRate
            if let float = pcm.floatChannelData {
                samples.append(contentsOf: UnsafeBufferPointer(start: float[0], count: count))
            } else if let int16 = pcm.int16ChannelData {
                let channel = int16[0]
                for index in 0..<count {
                    samples.append(Float(channel[index]) / Float(Int16.max))
                }
            }
        }

        /// Resumes the caller once, with the audio or an error.
        func finish(_ result: Result<SpokenAudio, Error>?) {
            lock.lock()
            let waiting = continuation
            continuation = nil
            let audio = SpokenAudio(samples: samples, sampleRate: sampleRate)
            lock.unlock()
            waiting?.resume(with: result ?? .success(audio))
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            finish(nil)
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
            finish(.failure(TTSError.synthesisFailed("the system synthesizer cancelled the utterance")))
        }
    }

    private static func render(text: String, options: SynthesisOptions) async throws -> SpokenAudio {
        let utterance = AVSpeechUtterance(string: text)
        if let voiceID = options.voice?.id, let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: options.language)
        }
        // Map our 1.0-is-normal multiplier onto AVSpeech's rate scale.
        let scaled = AVSpeechUtteranceDefaultSpeechRate * Float(options.rate)
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, scaled))

        var session: Session?
        let audio = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SpokenAudio, Error>) in
            let started = Session(sampleRate: options.sampleRate, continuation: continuation)
            session = started
            started.synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                started.append(pcm)
            }
        }
        // The synthesizer holds its delegate weakly; keep the session alive
        // until the utterance is done.
        withExtendedLifetime(session) {}
        return audio
    }
}
