//
//  SynthesisOptions.swift
//  SpeechSynthesizer
//
//  Per-request configuration for a synthesis call.
//

import Foundation

/// Options for a single ``TTSEngine/synthesize(_:options:)`` call.
public struct SynthesisOptions: Sendable {

    /// The voice to speak in. `nil` uses the engine's default voice.
    public var voice: TTSVoice?

    /// The BCP-47 language tag (used when `voice` is `nil` or multilingual).
    public var language: String

    /// Speaking rate multiplier — `1.0` is normal. Clamped to `0.25...4.0`.
    public var rate: Double

    /// The desired output sample rate in hertz.
    public var sampleRate: Double

    /// Create synthesis options.
    ///
    /// - Parameters:
    ///   - voice: The voice, or `nil` for the engine default.
    ///   - language: BCP-47 language tag. Default `en-US`.
    ///   - rate: Speaking-rate multiplier (`1.0` = normal). Clamped `0.25...4.0`.
    ///   - sampleRate: Output sample rate in hertz. Default `24000`.
    public init(
        voice: TTSVoice? = nil,
        language: String = "en-US",
        rate: Double = 1.0,
        sampleRate: Double = 24_000
    ) {
        self.voice = voice
        self.language = language
        self.rate = min(4.0, max(0.25, rate))
        self.sampleRate = sampleRate
    }
}
