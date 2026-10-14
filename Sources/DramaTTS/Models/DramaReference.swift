//
//  DramaReference.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//

import Foundation
import SpeechSynthesizer

/// A voice to clone: a clip and exactly what is said in it.
///
/// The Fish Audio Community License forbids cloning a real person's voice
/// without their consent.
public struct DramaReference: Sendable, Equatable {

    /// The clip, any sample rate; 5–30 s of one speaker works best.
    public var audio: SpokenAudio

    /// Its transcript, word for word.
    public var transcript: String

    /// - Parameters:
    ///   - audio: The clip.
    ///   - transcript: What is said in it.
    public init(audio: SpokenAudio, transcript: String) {
        self.audio = audio
        self.transcript = transcript
    }
}
