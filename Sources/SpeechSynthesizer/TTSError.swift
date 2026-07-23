//
//  TTSError.swift
//  SpeechSynthesizer
//
//  Errors surfaced by TTS engines.
//

import Foundation

/// An error from a TTS engine.
public enum TTSError: Error, LocalizedError, Equatable, Sendable {

    /// `synthesize` was called before `prepare`.
    case notPrepared

    /// The model's weights failed to download.
    case modelDownloadFailed(String)

    /// The requested voice isn't offered by this model.
    case unsupportedVoice(String)

    /// The text to synthesize was empty.
    case emptyText

    /// The underlying engine failed to synthesize.
    case synthesisFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notPrepared:
            return "The model isn't prepared. Call prepare() before synthesizing."
        case .modelDownloadFailed(let detail):
            return "Failed to download the model: \(detail)"
        case .unsupportedVoice(let id):
            return "Voice \"\(id)\" isn't available for this model."
        case .emptyText:
            return "There's no text to synthesize."
        case .synthesisFailed(let detail):
            return "Speech synthesis failed: \(detail)"
        }
    }
}
