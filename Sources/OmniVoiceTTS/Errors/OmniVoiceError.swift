//
//  OmniVoiceError.swift
//  OmniVoiceTTS
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Why OmniVoice could not run.
public enum OmniVoiceError: Error, LocalizedError, Equatable, Sendable {

    /// The engine was created without naming the licence version it accepts.
    case licenceNotAccepted(expected: String)

    /// This Mac has less memory than the model needs.
    case insufficientMemory(physicalGB: Double, requiredGB: Double)

    /// A file of the model is missing or unreadable.
    case modelMissing(String)

    /// The voice design names words outside the model's vocabulary.
    case invalidVoiceDesign(String)

    /// The language is not one the model knows.
    case unsupportedLanguage(String)

    /// Reference audio for cloning is unusable, has no transcript, or the
    /// model in hand cannot encode it.
    case invalidReference(String)

    public var errorDescription: String? {
        switch self {
        case .licenceNotAccepted(let expected):
            return "OmniVoice runs only after its licences (\(expected)) have been accepted."
        case .insufficientMemory(let physical, let required):
            return String(format: "OmniVoice needs a Mac with at least %.0f GB of memory; this one has %.0f GB.",
                          required, physical)
        case .modelMissing(let detail):
            return "OmniVoice's model is incomplete: \(detail)"
        case .invalidVoiceDesign(let detail):
            return detail
        case .unsupportedLanguage(let language):
            return "OmniVoice does not know the language '\(language)'"
        case .invalidReference(let detail):
            return detail
        }
    }
}
