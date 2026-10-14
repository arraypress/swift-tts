//
//  Resampling.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//

import Foundation
import SpeechSynthesizer

/// Mono sample-rate conversion for reference audio.
enum Resampling {

    /// `samples` at `from` Hz, converted to `to` Hz.
    static func resample(_ samples: [Float], from: Double, to: Double) throws -> [Float] {
        guard from != to, !samples.isEmpty else { return samples }
        guard let converted = SpokenAudio(samples: samples, sampleRate: from).resampled(to: to) else {
            throw DramaError.invalidReference("cannot convert reference audio to \(Int(to)) Hz")
        }
        return converted.samples
    }
}
