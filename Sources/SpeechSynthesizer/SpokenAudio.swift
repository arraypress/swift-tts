//
//  SpokenAudio.swift
//  SpeechSynthesizer
//
//  The output of every TTS engine — mono PCM samples plus a sample rate. Bridges
//  to a WAV file or an AVAudioPCMBuffer for playback, so callers never care which
//  engine produced the audio (the same role Transcript plays for transcription).
//

import Foundation
import AVFoundation

/// Synthesized speech: mono float PCM samples in `-1...1` at a given sample rate.
public struct SpokenAudio: Sendable, Equatable {

    /// Mono PCM samples, normalized to `-1...1`.
    public let samples: [Float]

    /// Samples per second (most on-device TTS models emit 24 kHz).
    public let sampleRate: Double

    /// Create spoken audio from raw samples.
    public init(samples: [Float], sampleRate: Double = 24_000) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    /// Duration in seconds.
    public var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(samples.count) / sampleRate
    }

    /// Whether there are no samples.
    public var isEmpty: Bool { samples.isEmpty }

    // MARK: - WAV

    /// Encode as a 16-bit PCM mono WAV file.
    public func wavData() -> Data {
        let bitsPerSample = 16
        let channels = 1
        let byteRate = Int(sampleRate) * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = samples.count * bitsPerSample / 8

        var data = Data()
        func appendString(_ string: String) { data.append(contentsOf: string.utf8) }
        func appendUInt32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func appendUInt16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }

        appendString("RIFF")
        appendUInt32(UInt32(36 + dataSize))
        appendString("WAVE")

        appendString("fmt ")
        appendUInt32(16)                       // PCM fmt chunk size
        appendUInt16(1)                        // audio format: PCM
        appendUInt16(UInt16(channels))
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(byteRate))
        appendUInt16(UInt16(blockAlign))
        appendUInt16(UInt16(bitsPerSample))

        appendString("data")
        appendUInt32(UInt32(dataSize))
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let value = Int16(clamped * Float(Int16.max))
            appendUInt16(UInt16(bitPattern: value))
        }
        return data
    }

    /// Write a 16-bit PCM WAV file to `url`.
    public func write(toWAV url: URL) throws {
        try wavData().write(to: url)
    }

    // MARK: - Playback

    /// A mono float32 `AVAudioPCMBuffer` for playback via `AVAudioEngine`.
    public func pcmBuffer() -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
