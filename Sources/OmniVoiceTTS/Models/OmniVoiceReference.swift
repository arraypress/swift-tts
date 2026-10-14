//
//  OmniVoiceReference.swift
//  OmniVoiceTTS
//
//  Created by David Sherlock on 2026.
//

import Foundation
import SpeechSynthesizer

/// A voice to clone: a clip of one speaker and exactly what they say in it.
///
/// The transcript is required. The reference implementation transcribes a
/// clip without one by downloading Whisper; this engine never downloads
/// anything, so the caller supplies it.
public struct OmniVoiceReference: Sendable, Equatable {

    /// The clip, any sample rate; 3–10 s is best, over 20 s degrades cloning.
    public var audio: SpokenAudio

    /// What is said in it, word for word.
    public var transcript: String

    public init(audio: SpokenAudio, transcript: String) {
        self.audio = audio
        self.transcript = transcript
    }
}
