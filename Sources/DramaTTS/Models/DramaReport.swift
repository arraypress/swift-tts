//
//  DramaReport.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What one request cost.
public struct DramaReport: Sendable, Equatable {

    /// Text chunks generated.
    public var chunks: Int

    /// Frames generated (~21.5 a second of audio).
    public var frames: Int

    /// Chunks that stopped at their frame cap rather than ending themselves.
    public var cappedChunks: Int

    /// Chunks that still ended in dead air after every rewind.
    public var silencedChunks: Int

    /// Times generation went back to the last speech and sampled again
    /// after running into dead air.
    public var rewinds: Int

    /// Seconds from the call to the first audio.
    public var firstAudioSeconds: Double?

    /// Peak MLX memory during the request, in bytes.
    public var peakMemoryBytes: Int
}
