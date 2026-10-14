//
//  DramaError.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Why Drama 3 could not run.
public enum DramaError: Error, LocalizedError, Equatable, Sendable {

    /// The engine was created without naming the licence version it accepts.
    case licenceNotAccepted(expected: String)

    /// This Mac has less memory than the model needs.
    case insufficientMemory(physicalGB: Double, requiredGB: Double)

    /// A file of the model is missing or unreadable.
    case modelMissing(String)

    /// The model's files do not describe Drama 3 as this port knows it.
    case unsupportedModel(String)

    /// The text cannot be spoken as given (empty, structural tokens, bad speaker tag).
    case invalidText(String)

    /// Reference audio for cloning is unusable, or has no transcript.
    case invalidReference(String)

    /// Generation stopped.
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .licenceNotAccepted(let expected):
            return "Drama 3 runs only after its licence (\(expected)) has been accepted."
        case .insufficientMemory(let physical, let required):
            return String(format: "Drama 3 needs a Mac with at least %.0f GB of memory; this one has %.0f GB.",
                          required, physical)
        case .modelMissing(let detail):
            return "Drama 3's model is incomplete: \(detail)"
        case .unsupportedModel(let detail):
            return "Not a Drama 3 model this version can run: \(detail)"
        case .invalidText(let detail):
            return detail
        case .invalidReference(let detail):
            return detail
        case .cancelled:
            return "Generation was cancelled."
        }
    }
}
