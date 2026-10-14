//
//  PatternRewriter.swift
//  SpeechSynthesizer
//
//  Created by David Sherlock on 2026.
//
//  Regular-expression replacement where the replacement is computed: each
//  match is handed to a closure that returns the new text, or `nil` to leave
//  that match as it was.
//

import Foundation

/// One match, with its capture groups and what surrounds it.
struct PatternMatch {

    /// The whole text being rewritten.
    let source: NSString

    /// Where the match is in ``source``.
    let range: NSRange

    /// Capture groups, `0` being the whole match; `nil` for a group that did not take part.
    let groups: [String?]

    subscript(_ index: Int) -> String? { index < groups.count ? groups[index] : nil }

    /// Up to `count` characters before the match.
    func before(_ count: Int = 24) -> String {
        let start = max(0, range.location - count)
        return source.substring(with: NSRange(location: start, length: range.location - start))
    }

    /// Up to `count` characters after the match.
    func after(_ count: Int = 24) -> String {
        let start = range.location + range.length
        return source.substring(with: NSRange(location: start, length: min(count, source.length - start)))
    }

    /// Whether a full stop the match swallowed was also the end of a
    /// sentence: the text ends, a line ends, or the next word starts with a
    /// capital ("…by 12 Jan. The next…").
    var endsSentence: Bool {
        let next = after(3)
        guard let first = next.first else { return true }
        if first.isNewline { return true }
        guard first.isWhitespace else { return false }
        let rest = next.drop { $0 == " " || $0 == "\t" }
        guard let letter = rest.first else { return true }
        return letter.isUppercase || letter.isNewline || letter == "\"" || letter == "“"
    }
}

enum PatternRewriter {

    /// `text` with every match of `pattern` replaced by `transform`'s
    /// result, or left alone where it returns `nil`.
    static func rewrite(
        _ text: String, _ pattern: String, options: NSRegularExpression.Options = [],
        _ transform: (PatternMatch) -> String?
    ) -> String {
        // An invalid pattern is a programming error in this file's callers,
        // all of which use literal patterns the unit tests exercise.
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            assertionFailure("invalid pattern: \(pattern)")
            return text
        }
        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = 0
        for match in matches {
            let groups = (0..<match.numberOfRanges).map { index -> String? in
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : source.substring(with: range)
            }
            guard let replacement = transform(PatternMatch(source: source, range: match.range, groups: groups)) else {
                continue
            }
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += replacement
            cursor = match.range.location + match.range.length
        }
        result += source.substring(from: cursor)
        return result
    }
}
