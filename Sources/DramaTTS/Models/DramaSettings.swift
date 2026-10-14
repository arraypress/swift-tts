//
//  DramaSettings.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// How Drama 3 samples and when it stops. The defaults are the reference recipe's.
public struct DramaSettings: Sendable, Equatable {

    /// Sampling temperature.
    public var temperature: Float

    /// Candidates kept before top-p.
    public var topK: Int

    /// Cumulative probability kept.
    public var topP: Float

    /// A fixed cap on frames per chunk (~21.5 a second), or nil to scale the
    /// cap to each chunk's text.
    public var maxFramesPerChunk: Int?

    /// Whether a chunk ends once its audio has been quiet for 3 s.
    public var stopsOnSilence: Bool

    /// A random seed, for repeatable output; nil draws one.
    public var seed: UInt64?

    /// Frames per streamed piece: 16 ≈ 0.74 s.
    public var streamingFrames: Int

    /// - Parameters:
    ///   - temperature: Sampling temperature (0.7).
    ///   - topK: Candidates kept before top-p (30).
    ///   - topP: Cumulative probability kept (0.7).
    ///   - maxFramesPerChunk: A fixed per-chunk cap, or nil to scale it to the text.
    ///   - stopsOnSilence: Whether 3 s of quiet ends a chunk.
    ///   - seed: A seed for repeatable output.
    ///   - streamingFrames: Frames per streamed piece.
    public init(temperature: Float = 0.7, topK: Int = 30, topP: Float = 0.7, maxFramesPerChunk: Int? = nil,
                stopsOnSilence: Bool = true, seed: UInt64? = nil, streamingFrames: Int = 16) {
        self.temperature = temperature
        self.topK = topK
        self.topP = topP
        self.maxFramesPerChunk = maxFramesPerChunk
        self.stopsOnSilence = stopsOnSilence
        self.seed = seed
        self.streamingFrames = streamingFrames
    }
}
