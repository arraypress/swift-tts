//
//  KokoroText.swift
//  KokoroTTS
//
//  Created by David Sherlock on 2026.
//
//  Cutting long text into pieces Kokoro can say in one pass.
//
//  The converted model takes at most 510 phonemes (ALBERT's 512-token window
//  less BOS and EOS) and 2,000 acoustic frames, and FluidAudio refuses
//  anything longer — `phonemeSequenceTooLong(745)` for a 144-word paragraph.
//  Its G2P makes about one phoneme per character of English prose (measured:
//  775 characters, 745 phonemes), so pieces are cut by characters well under
//  the limit, at sentence ends first, then at clause marks, then between
//  words. A piece that still overflows — digits, initials, a slow --rate —
//  is halved and tried again by the engine.
//

import Foundation

enum KokoroText {

    /// Characters per piece: about 300 phonemes, 20 seconds of speech at
    /// normal rate — headroom under 510 phonemes and 2,000 frames (50 s).
    static let pieceCharacters = 300

    /// Silence between pieces, in seconds. FluidAudio's G2P drops
    /// punctuation, so Kokoro leaves no gap where one sentence meets the
    /// next; the cut is always at a sentence or clause end, where a reader
    /// would pause anyway.
    static let pieceGap = 0.25

    /// ``pieceGap`` of silence at `sampleRate`.
    static func gap(sampleRate: Double) -> [Float] {
        [Float](repeating: 0, count: Int(pieceGap * sampleRate))
    }

    /// `text` as pieces of at most `limit` characters, cut at sentence ends,
    /// then clause marks, then spaces; consecutive short sentences share a
    /// piece. Text that already fits comes back whole.
    static func pieces(_ text: String, limit: Int = pieceCharacters) -> [String] {
        let trimmed = collapse(text)
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.count > limit else { return [trimmed] }
        let units = sentences(trimmed).flatMap { sentence -> [String] in
            guard sentence.count > limit else { return [sentence] }
            return clauses(sentence).flatMap { clause in
                clause.count > limit ? wordRuns(clause, limit: limit) : [clause]
            }
        }
        return pack(units, limit: limit)
    }

    /// Two pieces from one that overflowed: cut at the clause or sentence end
    /// nearest the middle, else at the space nearest the middle. `nil` for a
    /// single word, which cannot be cut.
    static func halves(_ text: String) -> (String, String)? {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count > 1 else { return nil }
        let middle = words.count / 2
        let marks = Set<Character>(".!?…;:,—–")
        // The word ending in a mark that is closest to the middle.
        let cut = (1..<words.count).filter { index in
            words[index - 1].trimmingCharacters(in: closers).last.map(marks.contains) ?? false
        }.min { abs($0 - middle) < abs($1 - middle) } ?? middle
        return (words[..<cut].joined(separator: " "), words[cut...].joined(separator: " "))
    }

    // MARK: - Steps

    /// Closing quotes and brackets that may follow a full stop.
    static let closers = CharacterSet(charactersIn: "\"'”’)]»")

    /// One line of single-spaced text.
    static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func sentences(_ text: String) -> [String] {
        split(text, after: #"[.!?…]["'”’)\]»]*"#)
    }

    static func clauses(_ text: String) -> [String] {
        split(text, after: #"[,;:—–]["'”’)\]»]*|\s[-–—]"#)
    }

    /// `text` cut after each match of `pattern` that a space follows.
    static func split(_ text: String, after pattern: String) -> [String] {
        text.replacingOccurrences(of: "(\(pattern))\\s+", with: "$1\u{1F}", options: .regularExpression)
            .components(separatedBy: "\u{1F}")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Words packed into runs of at most `limit` characters. One word longer
    /// than `limit` is a run of its own.
    static func wordRuns(_ text: String, limit: Int) -> [String] {
        pack(text.split(separator: " ").map(String.init), limit: limit)
    }

    /// Consecutive units joined with spaces while they fit in `limit`.
    static func pack(_ units: [String], limit: Int) -> [String] {
        var pieces: [String] = []
        var current = ""
        for unit in units {
            if current.isEmpty {
                current = unit
            } else if current.count + 1 + unit.count <= limit {
                current += " " + unit
            } else {
                pieces.append(current)
                current = unit
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }
}
