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

    /// Create a voice descriptor.
    public init(id: String, name: String, language: String, model: TTSModel) {
        self.id = id
        self.name = name
        self.language = language
        self.model = model
    }
}
