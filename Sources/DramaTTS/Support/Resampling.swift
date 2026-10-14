//
//  Resampling.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//

import AVFoundation
import Foundation

/// Mono sample-rate conversion for reference audio.
enum Resampling {

    /// `samples` at `from` Hz, converted to `to` Hz.
    static func resample(_ samples: [Float], from: Double, to: Double) throws -> [Float] {
        guard from != to, !samples.isEmpty else { return samples }
        guard let input = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: from, channels: 1,
                                        interleaved: false),
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: to, channels: 1,
                                         interleaved: false),
              let converter = AVAudioConverter(from: input, to: output),
              let source = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: AVAudioFrameCount(samples.count))
        else { throw DramaError.invalidReference("cannot convert reference audio to \(Int(to)) Hz") }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        source.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let capacity = AVAudioFrameCount(Double(samples.count) * to / from) + 1024
        guard let target = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else {
            throw DramaError.invalidReference("cannot allocate converted audio")
        }
        var supplied = false
        var failure: NSError?
        let status = converter.convert(to: target, error: &failure) { _, state in
            if supplied {
                state.pointee = .endOfStream
                return nil
            }
            supplied = true
            state.pointee = .haveData
            return source
        }
        guard status != .error else {
            throw DramaError.invalidReference("reference conversion failed: \(failure?.localizedDescription ?? "")")
        }
        return Array(UnsafeBufferPointer(start: target.floatChannelData![0], count: Int(target.frameLength)))
    }
}
