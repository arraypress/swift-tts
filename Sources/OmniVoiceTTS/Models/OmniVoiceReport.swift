//
//  OmniVoiceReport.swift
//  OmniVoiceTTS
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What one request did and cost.
public struct OmniVoiceReport: Sendable, Equatable {

    /// Pieces the text was split into.
    public var chunks: Int

    /// Inline cues removed because the model would have read them aloud.
    public var droppedTags: [String]

    /// Question tags moved to where they work.
    public var movedTags: [String]

    /// The voice design as the model was given it, if any.
    public var voiceDesign: String?

    /// The language code the model was given; nil when it detected the language.
    public var language: String?

    /// Seconds from the call to the first audio.
    public var firstAudioSeconds: Double?

    /// Peak MLX memory during the request, in bytes.
    public var peakMemoryBytes: Int
}
