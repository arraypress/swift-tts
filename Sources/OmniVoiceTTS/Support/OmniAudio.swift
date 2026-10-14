//
//  OmniAudio.swift
//  OmniVoiceTTS
//
//  Created by David Sherlock on 2026.
//
//  The reference's post-processing, which the MLX port leaves out (it only
//  normalises the peak and fades 20 ms): pauses longer than a second are cut
//  to a second (pydub's split_on_silence at −50 dBFS, 500 ms kept either
//  side), leading and trailing silence trimmed to 100 ms, a 100 ms fade at
//  each end, and pieces joined with 100 ms of silence between them. Done per
//  piece so long text streams and never has to be held whole.
//

import Foundation

/// Sample-level clean-up of generated speech.
enum OmniAudio {

    /// Below this a 10 ms frame counts as silence (the reference's −50 dBFS).
    static let silenceDB: Float = -50

    /// Analysis frame, in seconds (pydub's 10 ms seek step).
    static let frameSeconds = 0.01

    /// RMS level of each 10 ms frame, in dBFS.
    static func frameLevels(_ samples: [Float], sampleRate: Double) -> [Float] {
        let size = max(1, Int(sampleRate * frameSeconds))
        return stride(from: 0, to: samples.count, by: size).map { start in
            let end = min(samples.count, start + size)
            var sum: Float = 0
            for index in start..<end { sum += samples[index] * samples[index] }
            let rms = (sum / Float(end - start)).squareRoot()
            return rms > 0 ? 20 * log10(rms) : -120
        }
    }

    /// Pauses longer than `longest` seconds shortened to `longest`; the
    /// first `lead` and last `trail` seconds of silence kept at the edges.
    static func tightened(_ samples: [Float], sampleRate: Double, longest: Double = 1.0, lead: Double = 0.1,
                          trail: Double = 0.1) -> [Float] {
        let size = max(1, Int(sampleRate * frameSeconds))
        let levels = frameLevels(samples, sampleRate: sampleRate)
        guard let firstSound = levels.firstIndex(where: { $0 >= silenceDB }),
              let lastSound = levels.lastIndex(where: { $0 >= silenceDB }) else { return [] }
        let leadFrames = Int(lead / frameSeconds), trailFrames = Int(trail / frameSeconds)
        let keepFrames = Int(longest / frameSeconds)
        let startFrame = max(0, firstSound - leadFrames)
        let endFrame = min(levels.count, lastSound + 1 + trailFrames)

        var output: [Float] = []
        output.reserveCapacity(samples.count)
        var frame = startFrame
        while frame < endFrame {
            if levels[frame] < silenceDB {
                var runEnd = frame
                while runEnd < endFrame, levels[runEnd] < silenceDB { runEnd += 1 }
                let run = runEnd - frame
                if run > keepFrames {
                    // Keep half the allowance on each side of the cut.
                    let head = keepFrames / 2
                    append(frames: frame..<(frame + head), of: samples, size: size, to: &output)
                    append(frames: (runEnd - (keepFrames - head))..<runEnd, of: samples, size: size, to: &output)
                } else {
                    append(frames: frame..<runEnd, of: samples, size: size, to: &output)
                }
                frame = runEnd
            } else {
                append(frames: frame..<(frame + 1), of: samples, size: size, to: &output)
                frame += 1
            }
        }
        return output
    }

    private static func append(frames: Range<Int>, of samples: [Float], size: Int, to output: inout [Float]) {
        let start = min(samples.count, frames.lowerBound * size)
        let end = min(samples.count, frames.upperBound * size)
        if start < end { output += samples[start..<end] }
    }

    /// A linear fade over the first `fadeIn` and last `fadeOut` seconds.
    static func faded(_ samples: [Float], sampleRate: Double, fadeIn: Double = 0.1, fadeOut: Double = 0.1) -> [Float] {
        var output = samples
        let inCount = min(Int(fadeIn * sampleRate), output.count / 2)
        let outCount = min(Int(fadeOut * sampleRate), output.count / 2)
        if inCount > 1 {
            for index in 0..<inCount { output[index] *= Float(index) / Float(inCount - 1) }
        }
        if outCount > 1 {
            let base = output.count - outCount
            for index in 0..<outCount { output[base + index] *= Float(outCount - 1 - index) / Float(outCount - 1) }
        }
        return output
    }

    /// Silence of `seconds`.
    static func silence(_ seconds: Double, sampleRate: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * sampleRate))
    }

    /// One generated piece made ready to play: pauses tightened, ends faded,
    /// 100 ms of silence before the first piece and after every piece.
    static func finished(_ samples: [Float], sampleRate: Double, isFirst: Bool) -> [Float] {
        let tight = tightened(samples, sampleRate: sampleRate)
        guard !tight.isEmpty else { return [] }
        let padding = silence(0.1, sampleRate: sampleRate)
        return (isFirst ? padding : []) + faded(tight, sampleRate: sampleRate) + padding
    }

    /// Reference audio as the reference prepares it: lifted to an RMS of 0.1
    /// when quieter, pauses over 400 ms shortened, edges trimmed (100 ms
    /// lead, 200 ms trail).
    static func preparedReference(_ samples: [Float], sampleRate: Double) -> [Float] {
        let rms = (samples.reduce(0) { $0 + $1 * $1 } / Float(max(1, samples.count))).squareRoot()
        let lifted = rms > 0 && rms < 0.1 ? samples.map { $0 * 0.1 / rms } : samples
        return tightened(lifted, sampleRate: sampleRate, longest: 0.4, lead: 0.1, trail: 0.2)
    }
}
