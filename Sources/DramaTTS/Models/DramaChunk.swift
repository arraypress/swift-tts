//
//  DramaChunk.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// A piece of streamed speech.
public struct DramaChunk: Sendable, Equatable {

    /// Mono samples in −1…1 at ``sampleRate``.
    public var samples: [Float]

    /// Samples per second (44 100).
    public var sampleRate: Double

    /// Which text chunk this audio belongs to.
    public var segment: Int

    /// Whether this is the closing piece, which carries no audio and the ``report``.
    public var isFinal: Bool

    /// What the request cost, on the closing piece.
    public var report: DramaReport?
}
