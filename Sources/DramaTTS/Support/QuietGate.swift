//
//  QuietGate.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  Applies ``SilenceRule`` to streamed pieces. Dead-air pieces are held back
//  rather than played: if speech resumes they go out with it (a pause), and if
//  dead air reaches the rule's limit only the kept tail goes out and the chunk
//  stops — so a runaway's hiss is never heard.
//

import Foundation

/// Holds back dead air and decides when a chunk has stopped speaking.
struct QuietGate: Sendable {

    /// The rule.
    let rule: SilenceRule

    /// Samples per second.
    let sampleRate: Double

    /// Dead-air samples held back so far.
    private(set) var held: [Float] = []

    /// - Parameters:
    ///   - rule: What counts as dead air, and for how long.
    ///   - sampleRate: Samples per second.
    init(rule: SilenceRule, sampleRate: Double) {
        self.rule = rule
        self.sampleRate = sampleRate
    }

    /// RMS level in dBFS; digital silence reads as −200.
    static func level<C: Collection>(_ samples: C) -> Float where C.Element == Float {
        guard !samples.isEmpty else { return -200 }
        let power = samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)
        return power > 0 ? 10 * log10(power) : -200
    }

    /// The standard deviation, in dB, of the levels of consecutive sub-windows:
    /// speech rises and falls with its syllables; hiss does not.
    static func spread(_ samples: [Float], window: Int) -> Float {
        guard window > 0, samples.count >= 2 * window else { return .infinity }
        let levels = stride(from: 0, to: samples.count - window + 1, by: window).map {
            max(level(samples[$0 ..< $0 + window]), -120)
        }
        let mean = levels.reduce(0, +) / Float(levels.count)
        let variance = levels.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(levels.count)
        return variance.squareRoot()
    }

    /// Whether a piece is dead air under the rule.
    func isDeadAir(_ piece: [Float]) -> Bool {
        let loudness = Self.level(piece)
        if loudness < rule.silenceDB { return true }
        guard loudness < rule.quietDB else { return false }
        return Self.spread(piece, window: Int(rule.subWindow * sampleRate)) < rule.flatSpreadDB
    }

    /// Takes the next piece; returns what may be played now, and whether the
    /// chunk should stop.
    mutating func pass(_ piece: [Float]) -> (emit: [Float], stop: Bool) {
        guard isDeadAir(piece) else {
            defer { held = [] }
            return (held + piece, false)
        }
        held += piece
        guard Double(held.count) >= rule.maximumQuiet * sampleRate else { return ([], false) }
        let kept = Array(held.prefix(Int(rule.keptTail * sampleRate)))
        held = []
        return (kept, true)
    }

    /// Releases whatever is held, at a chunk's natural end.
    mutating func flush() -> [Float] {
        defer { held = [] }
        return held
    }
}
