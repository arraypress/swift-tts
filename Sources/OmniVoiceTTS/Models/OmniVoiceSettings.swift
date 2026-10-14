//
//  OmniVoiceSettings.swift
//  OmniVoiceTTS
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// How one OmniVoice request sounds and how hard it works. The defaults are
/// the reference's.
public struct OmniVoiceSettings: Sendable, Equatable {

    /// A voice from the fixed vocabulary — `"male, elderly, low pitch, british accent"`
    /// (see ``VoiceDesignVocabulary``); nil lets the model choose.
    public var voiceDesign: String?

    /// The language — a code, name or BCP-47 tag (see ``OmniLanguages``);
    /// nil lets the model work it out from the text.
    public var language: String?

    /// A voice to clone: a clip and what is said in it. Overrides the
    /// voice-design's choice of speaker.
    public var reference: OmniVoiceReference?

    /// A seed, for repeatable output; nil continues from MLX's random state.
    public var seed: UInt64?

    /// Diffusion steps: 32 (the reference) or fewer for speed — 16 measured
    /// word-perfect on English at nearly twice the speed.
    public var steps: Int

    /// Speaking speed: 1 is the model's own pace.
    public var speed: Double

    /// Classifier-free guidance (2.0).
    public var guidanceScale: Double

    /// Whether, without a reference, the first piece of a long text becomes
    /// the reference for the rest, so the voice does not drift between
    /// pieces — what the reference implementation does.
    public var keepsVoiceAcrossChunks: Bool

    /// Whether cues the model would read aloud are removed and sentence-final
    /// question tags moved (``OmniTags/filter(_:)``). Off sends the text as
    /// written — for measuring the model, not for speech.
    public var filtersTags: Bool

    /// - Parameters:
    ///   - voiceDesign: Fixed-vocabulary voice description, or nil.
    ///   - language: Language, or nil to detect it.
    ///   - reference: A voice to clone, or nil.
    ///   - seed: A seed for repeatable output.
    ///   - steps: Diffusion steps (32).
    ///   - speed: Speaking speed (1).
    ///   - guidanceScale: Guidance (2).
    ///   - keepsVoiceAcrossChunks: Anchor long text to its first piece (true).
    ///   - filtersTags: Remove cues the model would read aloud (true).
    public init(voiceDesign: String? = nil, language: String? = nil, reference: OmniVoiceReference? = nil,
                seed: UInt64? = nil, steps: Int = 32, speed: Double = 1, guidanceScale: Double = 2,
                keepsVoiceAcrossChunks: Bool = true, filtersTags: Bool = true) {
        self.voiceDesign = voiceDesign
        self.language = language
        self.reference = reference
        self.seed = seed
        self.steps = steps
        self.speed = speed
        self.guidanceScale = guidanceScale
        self.keepsVoiceAcrossChunks = keepsVoiceAcrossChunks
        self.filtersTags = filtersTags
    }
}
