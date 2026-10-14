//
//  FrameBudget.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  How many frames one chunk may run to. The reference caps every chunk at
//  1024 frames (47.6 s) whatever its length, so a chunk that never emits EOS —
//  a cue at the very start of a line did this: one sentence, then hiss to the
//  cap — costs 47 s of audio and ~14 GB more memory. Measured on the eight
//  probe lines, speech ran at 1.16–1.45 frames per UTF-8 byte; the budget
//  allows 4 per byte plus 3 s, about 2.5× the slowest line, under the
//  reference's own cap.
//

import Foundation

/// The per-chunk frame cap, scaled to the chunk's text.
enum FrameBudget {

    /// The reference's cap, never exceeded.
    static let ceiling = 1024

    /// Frames always allowed (≈3 s), for cues that take time but few bytes.
    static let floor = 64

    /// Frames allowed per UTF-8 byte of text.
    static let perByte = 4

    /// The cap for one chunk.
    static func maxFrames(for chunk: String) -> Int {
        min(ceiling, floor + perByte * chunk.utf8.count)
    }
}
