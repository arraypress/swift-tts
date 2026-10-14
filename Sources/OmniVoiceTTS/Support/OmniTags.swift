//
//  OmniTags.swift
//  OmniVoiceTTS
//
//  Created by David Sherlock on 2026.
//
//  OmniVoice was trained with thirteen non-verbal tags and nothing else.
//  Measured in the probe: any other bracket is READ ALOUD — "[whispers]"
//  comes out as the word "Whispers" — so a cue written for another engine
//  (Drama's [whispering], {feeling stressed}, <|speaker:1|>) must not reach
//  this one. Uppercase CMU pronunciations in brackets ("[B EY1 S]") are the
//  model's other inline control and pass through.
//
//  The question sounds are word-like tags, and where they sit decides
//  whether the clip survives: last on a line, or after the sentence's
//  punctuation, they turned whole clips into noise. Measured, and moved to
//  the one place that worked every time; see ``placeQuestionTags(_:)``.
//

import Foundation

/// The inline tags OmniVoice understands, and the filter that keeps the rest out.
public enum OmniTags {

    /// The thirteen tags the model was trained with (k2-fsa/OmniVoice README).
    public static let supported: [String] = [
        "laughter", "sigh", "confirmation-en", "question-en", "question-ah", "question-oh", "question-ei",
        "question-yi", "surprise-ah", "surprise-oh", "surprise-wa", "surprise-yo", "dissatisfaction-hnn",
    ]

    /// What filtering did to a text.
    public struct Filtered: Sendable, Equatable {
        /// The text to send to the model.
        public var text: String
        /// Tags and cues removed because the model would have read them aloud.
        public var dropped: [String]
        /// Question tags moved to where they work (see ``placeQuestionTags(_:)``).
        public var moved: [String]
    }

    /// Removes every bracket, brace and speaker cue the model does not know,
    /// keeps the thirteen tags and CMU pronunciations, and moves question tags
    /// to where they work.
    public static func filter(_ text: String) -> Filtered {
        var dropped: [String] = []
        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if let (cue, end) = cue(in: text, at: index) {
                if keeps(cue) {
                    output += cue
                } else {
                    dropped.append(cue)
                    // A removed cue leaves one space at most between its neighbours.
                    if !(output.last?.isWhitespace ?? true) { output += " " }
                    index = end
                    while index < text.endIndex, text[index] == " " || text[index] == "\t" {
                        index = text.index(after: index)
                    }
                    continue
                }
                index = end
                continue
            }
            output.append(character)
            index = text.index(after: index)
        }
        let tidied = output.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.replacingOccurrences(of: #"[ \t]+([,.;:!?])"#, with: "$1", options: .regularExpression)
                    .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
        let (placed, moved) = placeQuestionTags(tidied)
        return Filtered(text: placed, dropped: dropped, moved: moved)
    }

    /// Whether a cue is one the model handles.
    static func keeps(_ cue: String) -> Bool {
        guard cue.hasPrefix("["), cue.hasSuffix("]") else { return false }
        let body = String(cue.dropFirst().dropLast())
        if supported.contains(body) { return true }
        return isPronunciation(body)
    }

    /// `B EY1 S`: uppercase CMU phonemes, stress digits allowed, space-separated.
    static func isPronunciation(_ body: String) -> Bool {
        let parts = body.split(separator: " ")
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { part in
            guard let first = part.first, first.isASCII, first.isUppercase else { return false }
            return part.allSatisfy { ($0.isASCII && $0.isUppercase) || ("0"..."2").contains($0) }
        }
    }

    /// A bracketed `[…]`, braced `{…}` or `<|…|>` cue starting at `index`,
    /// without nesting or line breaks inside.
    static func cue(in text: String, at index: String.Index) -> (String, String.Index)? {
        let character = text[index]
        let closing: String
        switch character {
        case "[": closing = "]"
        case "{": closing = "}"
        case "<":
            let next = text.index(after: index)
            guard next < text.endIndex, text[next] == "|" else { return nil }
            closing = "|>"
        default: return nil
        }
        let rest = text[text.index(after: index)...]
        guard let range = rest.range(of: closing) else { return nil }
        let inside = rest[rest.startIndex..<range.lowerBound]
        if inside.contains(where: { $0.isNewline || $0 == "[" || $0 == "{" }) { return nil }
        return (String(text[index..<range.upperBound]), range.upperBound)
    }

    /// Places every question tag where it was measured to work: inside its
    /// sentence, just before a closing "?" — "You are leaving already [question-en]?".
    ///
    /// Measured on four seeds each (Swift port, 32 steps, transcribed back):
    /// the tag last on the line, after the words ("…already [question-en]")
    /// broke 2 of 4 clips into noise; after the punctuation ("…already?
    /// [question-en]", "…already. [question-en]") 4 of 4; first on the line
    /// 3 of 4. Before a closing "?" it broke none, and the question sound was
    /// heard; so was a tag with more words after it in the sentence, which is
    /// left alone. Confirmation and surprise tags were not affected.
    static func placeQuestionTags(_ text: String) -> (String, [String]) {
        var moved: [String] = []
        var result = text
        let tag = #"\[(question-(?:en|ah|oh|ei|yi))\]"#
        // Last in its sentence: "X [q]", "X? [q]", "X. [q]", "X [q]." → "X [q]?".
        let trailing = try! NSRegularExpression(pattern:
            #"([^\s.?!])[ \t]*[.?!…]*[ \t]*"# + tag + #"[ \t]*[.?!…]*(?=[ \t]*(?:\r?\n|$))"#)
        // First in its sentence: "[q] X." → "X [q]?".
        let leading = try! NSRegularExpression(pattern:
            #"(^|\n|[.?!…][ \t]+)"# + tag + #"[ \t]*([^.?!…\n\[]*[^.?!…\n\[ \t])[ \t]*[.?!…]?"#,
            options: [.anchorsMatchLines])
        for (regex, template) in [(trailing, "$1 [$2]?"), (leading, "$1$3 [$2]?")] {
            let range = NSRange(result.startIndex..., in: result)
            for match in regex.matches(in: result, range: range) {
                let original = (result as NSString).substring(with: match.range)
                let replaced = regex.replacementString(for: match, in: result, offset: 0, template: template)
                if original != replaced { moved.append("[" + (result as NSString).substring(with: match.range(at: 2)) + "]") }
            }
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }
        return (result, moved)
    }
}
