//
//  OmniText.swift
//  OmniVoiceTTS
//
//  Created by David Sherlock on 2026.
//
//  OmniVoice generates a whole utterance at once — a diffusion model over a
//  fixed-length window, attention across all of it — so long text is split
//  before it reaches the model, as the reference does: when the estimated
//  audio passes 30 s, into ~15 s pieces at punctuation, never after an
//  abbreviation ("Mr.", "e.g."). Ported from k2-fsa/OmniVoice
//  (omnivoice/utils/text.py `chunk_text_punctuation`, utils/duration.py's
//  rule estimator as mlx-audio-swift carries it; both Apache-2.0 / MIT).
//

import Foundation

/// Text preparation for OmniVoice: duration estimates and chunking.
public enum OmniText {

    /// Audio frames per second (24 kHz, hop 960).
    public static let framesPerSecond = 25.0

    /// Above this estimated length the text is split (the reference's 30 s).
    public static let chunkThresholdSeconds = 30.0

    /// The length each piece aims for (the reference's 15 s).
    public static let chunkSeconds = 15.0

    static let splitPunctuation: Set<Character> = Set(".,;:!?。，；：！？")
    static let closingMarks: Set<Character> = Set("\"'“”‘’）]》>」】")
    static let endPunctuation: Set<Character> = Set(";:,.!?…)]}\"'“”‘’；：，。！？、）】")
    static let abbreviations: Set<String> = [
        "Mr.", "Mrs.", "Ms.", "Dr.", "Prof.", "Sr.", "Jr.", "Rev.", "Fr.", "Hon.", "Pres.", "Gov.", "Capt.", "Gen.",
        "Sen.", "Rep.", "Col.", "Maj.", "Lt.", "Cmdr.", "Sgt.", "Cpl.", "Co.", "Corp.", "Inc.", "Ltd.", "Est.", "Dept.",
        "St.", "Ave.", "Blvd.", "Rd.", "Mt.", "Ft.", "No.", "Jan.", "Feb.", "Mar.", "Apr.", "Aug.", "Sep.", "Sept.",
        "Oct.", "Nov.", "Dec.", "i.e.", "e.g.", "vs.", "Vs.", "Etc.", "approx.", "fig.", "def.",
    ]

    /// Newlines become spaces, runs of spaces collapse, and spaces beside
    /// Chinese characters go (as the reference's `_combine_text` does) — the
    /// model reads one line.
    public static func flatten(_ text: String) -> String {
        text.replacingOccurrences(of: #"[\r\n]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=[\x{4E00}-\x{9FFF}])\s+|\s+(?=[\x{4E00}-\x{9FFF}])"#, with: "",
                                  options: .regularExpression)
            .replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")")
            .trimmingCharacters(in: .whitespaces)
    }

    /// The pieces to generate one at a time: the text whole when its
    /// estimated audio is under ``chunkThresholdSeconds``, otherwise split at
    /// punctuation into pieces of about ``chunkSeconds``.
    public static func chunks(_ text: String, speed: Double = 1) -> [String] {
        let flat = flatten(text)
        guard !flat.isEmpty else { return [] }
        let frames = estimatedFrames(flat, speed: speed)
        guard Double(frames) > chunkThresholdSeconds * framesPerSecond else { return [flat] }
        let framesPerCharacter = Double(frames) / Double(flat.count)
        let length = max(1, Int(chunkSeconds * framesPerSecond / framesPerCharacter))
        return chunkAtPunctuation(flat, length: length, minimumLength: 3)
    }

    /// The reference's `chunk_text_punctuation`: sentences split at
    /// punctuation (not after an abbreviation), merged up to `length`
    /// characters, an undersized piece folded into its neighbour.
    static func chunkAtPunctuation(_ text: String, length: Int, minimumLength: Int?) -> [String] {
        var sentences: [[Character]] = []
        var current: [Character] = []
        for character in text {
            if current.isEmpty, !sentences.isEmpty,
               splitPunctuation.contains(character) || closingMarks.contains(character) {
                sentences[sentences.count - 1].append(character)
                continue
            }
            current.append(character)
            guard splitPunctuation.contains(character) else { continue }
            if character == ".",
               let lastWord = String(current).trimmingCharacters(in: .whitespaces).split(separator: " ").last,
               abbreviations.contains(String(lastWord)) {
                continue
            }
            sentences.append(current)
            current = []
        }
        if !current.isEmpty { sentences.append(current) }

        var merged: [[Character]] = []
        var chunk: [Character] = []
        for sentence in sentences {
            if chunk.count + sentence.count <= length {
                chunk += sentence
            } else {
                if !chunk.isEmpty { merged.append(chunk) }
                chunk = sentence
            }
        }
        if !chunk.isEmpty { merged.append(chunk) }

        var final = merged
        if let minimumLength {
            final = []
            let firstIsShort = (merged.first?.count ?? minimumLength) < minimumLength
            for (index, piece) in merged.enumerated() {
                if index == 1 && firstIsShort {
                    final[final.count - 1] += piece
                } else if piece.count >= minimumLength || final.isEmpty {
                    final.append(piece)
                } else {
                    final[final.count - 1] += piece
                }
            }
        }
        return final.map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Ends `text` with punctuation if it has none (the reference does this
    /// to a clone's transcript).
    public static func punctuated(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last, !endPunctuation.contains(last) else { return trimmed }
        return trimmed + (VoiceDesignVocabulary.containsHan(trimmed) ? "。" : ".")
    }

    // MARK: Known weak spots

    /// Scripts whose tokenization in swift-transformers differs from the
    /// reference's: measured against Hugging Face `tokenizers` on 25 languages
    /// in 18 scripts, only Thai and Khmer came out different (Swift BPE returns whole words
    /// the reference splits), and the model then dropped words — Thai
    /// round-tripped at 51 % character error against the reference's 4 %.
    static let mistokenizedScripts: [(name: String, range: ClosedRange<UInt32>)] = [
        ("Thai", 0x0E00...0x0E7F), ("Khmer", 0x1780...0x17FF),
    ]

    /// A warning when `text` is in a script the tokenizer gets wrong, or nil.
    public static func tokenizerCaveat(_ text: String) -> String? {
        let hits = mistokenizedScripts.filter { script in
            text.unicodeScalars.contains { script.range.contains($0.value) }
        }
        guard !hits.isEmpty else { return nil }
        return hits.map(\.name).joined(separator: " and ")
            + " text is tokenized differently from the reference here, and words may be dropped"
    }

    // MARK: Duration

    /// Frames the model is given for `text` — the reference's rule estimate
    /// against "Nice to meet you." = 25 frames, with a 15 % margin.
    public static func estimatedFrames(_ text: String, speed: Double = 1) -> Int {
        let base = max(10, Int(ruleFrames(text) * 1.15))
        return max(1, speed > 0 && speed != 1 ? Int(Double(base) / speed) : base)
    }

    /// Estimated seconds of speech for `text`.
    public static func estimatedSeconds(_ text: String, speed: Double = 1) -> Double {
        Double(estimatedFrames(text, speed: speed)) / framesPerSecond
    }

    static func ruleFrames(_ text: String) -> Double {
        let referenceWeight = phoneticWeight("Nice to meet you.")
        let estimated = phoneticWeight(text) / (referenceWeight / 25)
        if estimated < 50 { return 50 * pow(estimated / 50, 1.0 / 3.0) }
        return estimated
    }

    static func phoneticWeight(_ text: String) -> Double {
        text.unicodeScalars.reduce(0) { $0 + weight(of: $1) }
    }

    static func weight(of scalar: Unicode.Scalar) -> Double {
        let code = scalar.value
        if (65...90).contains(code) || (97...122).contains(code) { return 1.0 }
        if code == 32 { return 0.2 }
        if code == 0x0640 { return 0 }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return 0
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation,
             .finalPunctuation, .otherPunctuation, .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            return 0.5
        case .spaceSeparator, .lineSeparator, .paragraphSeparator:
            return 0.2
        case .decimalNumber, .letterNumber, .otherNumber:
            return 3.5
        default:
            return scriptWeight(code)
        }
    }

    /// Weight by script block, as the reference tabulates it.
    static func scriptWeight(_ code: UInt32) -> Double {
        let table: [(UInt32, Double)] = [
            (0x02AF, 1.0), (0x03FF, 1.0), (0x052F, 1.0), (0x058F, 1.0), (0x05FF, 1.5), (0x08FF, 1.5), (0x0DFF, 1.8),
            (0x0EFF, 1.5), (0x0FFF, 1.8), (0x109F, 1.8), (0x10FF, 1.0), (0x11FF, 2.5), (0x139F, 3.0), (0x17FF, 1.8),
            (0x1C7F, 1.8), (0x1C8F, 1.0), (0x1CBF, 1.0), (0x1CFF, 1.8), (0x1EFF, 1.0), (0x309F, 2.2), (0x30FF, 2.2),
            (0x312F, 3.0), (0x318F, 2.5), (0x9FFF, 3.0), (0xA4CF, 3.0), (0xA69F, 1.0), (0xA7FF, 1.0), (0xA8FF, 1.8),
            (0xA97F, 2.5), (0xAADF, 1.8), (0xAB2F, 3.0), (0xAB6F, 1.0), (0xABFF, 1.8), (0xD7AF, 2.5), (0xFAFF, 3.0),
            (0xFEFF, 1.5), (0xFFEF, 1.0),
        ]
        for (limit, weight) in table where code <= limit { return weight }
        return code > 0x20000 ? 3.0 : 1.0
    }
}
