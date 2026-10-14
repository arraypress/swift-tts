//
//  TTSVoice.swift
//  SpeechSynthesizer
//
//  A selectable voice offered by a model.
//

import Foundation

/// A voice a model can speak in.
public struct TTSVoice: Hashable, Sendable, Identifiable {

    /// The engine-specific voice identifier (e.g. `"af_heart"` for Kokoro).
    public let id: String

    /// A human-readable name.
    public let name: String

    /// The BCP-47 language tag the voice speaks (e.g. `"en-US"`).
    public let language: String

    /// The model this voice belongs to.
    public let model: TTSModel

    /// The voice's own licence, when it differs from or adds to the model's.
    ///
    /// A preset voice is a recording of someone, and the recording carries
    /// its own terms: PocketTTS's weights are CC BY 4.0, but two of its
    /// English voices come from datasets licensed CC BY-NC. `nil` means the
    /// model's licence (``TTSModel/license``) covers the voice.
    public let license: String?

    /// Whether the voice may be used commercially. `false` for a voice taken
    /// from a non-commercial dataset, whatever the model's own licence.
    public let isCommercialUseAllowed: Bool

    /// Create a voice descriptor.
    public init(
        id: String, name: String, language: String, model: TTSModel,
        license: String? = nil, isCommercialUseAllowed: Bool = true
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.model = model
        self.license = license
        self.isCommercialUseAllowed = isCommercialUseAllowed
    }
}
