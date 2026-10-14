//
//  OmniVoiceChunk.swift
//  OmniVoiceTTS
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One piece of a streamed request: the audio for one piece of text, ready
/// to play or append, or — last — the report.
public struct OmniVoiceChunk: Sendable {

    /// Mono samples at ``sampleRate``; empty on the final element.
    public let samples: [Float]

    /// 24 kHz.
    public let sampleRate: Double

    /// Which piece of text this is, from 0.
    public let index: Int

    /// How many pieces the text was split into.
    public let count: Int

    /// The text this piece speaks (after tag filtering).
    public let text: String

    /// True on the last element, which carries ``report`` and no audio.
    public let isFinal: Bool

    /// What the request cost; set on the final element.
    public let report: OmniVoiceReport?
}
