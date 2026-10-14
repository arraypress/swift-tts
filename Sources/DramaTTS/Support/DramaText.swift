//
//  DramaText.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  The text rules of Drama 3's prompt, and splitting long text into chunks —
//  a port of the reference's chunking.py, kept to its exact behaviour. Work is
//  done on Unicode scalars, as Python iterates code points: a Swift Character
//  would make "\r\n" one unit and hide the "\n" sentence end inside it.
//
//  Chunks are about 300 bytes of UTF-8 with at most three speakers. Cuts prefer
//  sentence ends, then clause marks, then spaces. Special tokens, paired tags
//  (<whisper>…</whisper>) and [bracketed] cues are never cut, and every piece
//  of a speaker's turn keeps that speaker's tag.
//

import Foundation

/// Drama 3's text validation and chunking.
enum DramaText {

    /// Target UTF-8 bytes per generation chunk.
    static let chunkBytes = 300

    /// Most speakers in one chunk.
    static let chunkSpeakers = 3

    /// The tokenizer has `<|speaker:0|>` to `<|speaker:15|>`.
    static let maxSpeakerID = 15

    /// Written only by the prompt builder; text containing them would inject
    /// conversation structure or audio rows.
    static let structuralTokens = ["<|im_start|>", "<|im_end|>", "<|voice|>", "<|text|>", "<|interleave|>",
                                   "<|semantic:"]

    /// Unicode White_Space, as the reference strips it.
    static let whiteSpace: Set<Unicode.Scalar> = {
        let values: [UInt32] = Array(0x9 ... 0xD) + [0x20, 0x85, 0xA0, 0x1680] + Array(0x2000 ... 0x200A)
            + [0x2028, 0x2029, 0x202F, 0x205F, 0x3000]
        return Set(values.compactMap(Unicode.Scalar.init))
    }()

    static let sentenceEnds: Set<Unicode.Scalar> = Set(".!?;。！？；…\n".unicodeScalars)
    static let clauseMarks: Set<Unicode.Scalar> = Set(",:，：、".unicodeScalars)
    static let spaces: Set<Unicode.Scalar> = [" "]

    // swiftlint:disable force_try
    static let speakerTag = try! NSRegularExpression(pattern: #"<\|speaker:([0-9]+)\|>"#)
    static let uncuttable = try! NSRegularExpression(
        pattern: #"<\|[^|>]*\|>|<([A-Za-z][\w-]*)\b[^>]*>.*?</\1>|\[[^\[\]]*\]"#,
        options: [.dotMatchesLineSeparators])
    // swiftlint:enable force_try

    // MARK: - Rules

    /// The text with leading and trailing white space removed.
    static func strip(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        guard let first = scalars.firstIndex(where: { !whiteSpace.contains($0) }),
              let last = scalars.lastIndex(where: { !whiteSpace.contains($0) }) else { return "" }
        return string(scalars[first ... last])
    }

    /// The text with leading white space removed.
    static func stripLeading(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        guard let first = scalars.firstIndex(where: { !whiteSpace.contains($0) }) else { return "" }
        return string(scalars[first...])
    }

    /// Why the text cannot be spoken, or nil: empty, structural tokens, or a
    /// speaker tag outside 0…15.
    static func problem(with text: String, location: String) -> String? {
        if strip(text).isEmpty { return "\(location): text is empty" }
        for token in structuralTokens where text.contains(token) {
            return "\(location): text must not contain \(token)"
        }
        let ns = text as NSString
        var search = NSRange(location: 0, length: ns.length)
        while true {
            let found = ns.range(of: "<|speaker", options: [], range: search)
            if found.location == NSNotFound { break }
            var number = ""
            if let tag = speakerTag.firstMatch(in: text, options: [.anchored],
                                               range: NSRange(location: found.location,
                                                              length: ns.length - found.location)) {
                number = ns.substring(with: tag.range(at: 1))
            }
            if number.isEmpty || Int(number).map(String.init) != number || (Int(number) ?? .max) > maxSpeakerID {
                return "\(location): speaker tags run from <|speaker:0|> to <|speaker:\(maxSpeakerID)|>"
            }
            search = NSRange(location: found.location + 1, length: ns.length - found.location - 1)
        }
        return nil
    }

    /// Whether the text starts (after white space) with a speaker tag.
    static func startsWithSpeakerTag(_ text: String) -> Bool {
        let body = stripLeading(text)
        return speakerTag.firstMatch(in: body, options: [.anchored],
                                     range: NSRange(location: 0, length: (body as NSString).length)) != nil
    }

    /// Text that starts (after white space) with a speaker tag; speaker 0 by default.
    static func withSpeakerTag(_ text: String) -> String {
        startsWithSpeakerTag(text) ? text : "<|speaker:0|> \(text)"
    }

    /// A reference transcript whose tag directly follows "Text: " in the prompt.
    static func referenceTranscript(_ text: String) -> String {
        let tagged = withSpeakerTag(text)
        let body = stripLeading(tagged)
        let leading = string(tagged.unicodeScalars.prefix(tagged.unicodeScalars.count - body.unicodeScalars.count))
        let ns = body as NSString
        guard let tag = speakerTag.firstMatch(in: body, options: [.anchored],
                                              range: NSRange(location: 0, length: ns.length)) else { return tagged }
        return ns.substring(with: tag.range) + leading + ns.substring(from: tag.range.upperBound)
    }

    // MARK: - Chunking

    /// Generation chunks in order. Tagged turns are split per speaker, each
    /// piece re-tagged, then regrouped so a chunk stays within the byte limit
    /// and the speaker count.
    static func split(_ text: String, limit: Int = chunkBytes, maxSpeakers: Int = chunkSpeakers) -> [String] {
        let ns = text as NSString
        let tags = speakerTag.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !tags.isEmpty else { return splitByLength(text, limit: limit) }

        var turns: [(speaker: String, body: String)] = []
        var cursor = 0
        var speaker = "0"
        for tag in tags {
            turns.append((speaker, ns.substring(with: NSRange(location: cursor, length: tag.range.location - cursor))))
            speaker = ns.substring(with: tag.range(at: 1))
            cursor = tag.range.upperBound
        }
        turns.append((speaker, ns.substring(from: cursor)))

        let tagged = turns.flatMap { turn in
            splitByLength(turn.body, limit: limit).map { (turn.speaker, "<|speaker:\(turn.speaker)|> \($0)") }
        }
        var chunks: [[String]] = []
        var speakers: Set<String> = []
        var size = 0
        for (speaker, piece) in tagged {
            let isNew = !speakers.contains(speaker)
            if !chunks.isEmpty, (isNew && speakers.count >= maxSpeakers) || size + piece.utf8.count > limit {
                chunks.append([])
                speakers = []
                size = 0
            }
            if chunks.isEmpty { chunks.append([]) }
            chunks[chunks.count - 1].append(piece)
            speakers.insert(speaker)
            size += piece.utf8.count
        }
        return chunks.map { $0.joined(separator: "\n") }
    }

    /// Pieces packed into chunks of about `limit` bytes. An uncuttable span
    /// longer than the limit becomes a chunk of its own.
    static func splitByLength(_ text: String, limit: Int = chunkBytes) -> [String] {
        if strip(text).isEmpty { return [] }
        if text.utf8.count <= limit { return [text] }
        var chunks: [String] = []
        var current = ""
        for piece in pieces(text, limit: limit) {
            if !current.isEmpty && (current + piece).utf8.count > limit {
                chunks.append(current)
                current = ""
            }
            current += piece
        }
        chunks.append(current)
        return chunks.map(strip).filter { !$0.isEmpty }
    }

    /// The text cut into pieces, uncuttable spans kept whole.
    static func pieces(_ text: String, limit: Int) -> [String] {
        let ns = text as NSString
        var pieces: [String] = []
        var last = 0
        for match in uncuttable.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            pieces += freePieces(ns.substring(with: NSRange(location: last, length: match.range.location - last)),
                                 limit: limit)
            pieces.append(ns.substring(with: match.range))
            last = match.range.upperBound
        }
        return pieces + freePieces(ns.substring(from: last), limit: limit)
    }

    /// Free text cut at sentence ends, then fitted to the limit.
    static func freePieces(_ text: String, limit: Int) -> [String] {
        cutAfter(Array(text.unicodeScalars), marks: sentenceEnds)
            .flatMap { fit($0, limit: limit, marks: [clauseMarks, spaces]) }
            .map(string)
    }

    /// Cuts after every mark, except a period between two digits (3.14).
    static func cutAfter(_ text: [Unicode.Scalar], marks: Set<Unicode.Scalar>) -> [[Unicode.Scalar]] {
        var parts: [[Unicode.Scalar]] = []
        var start = 0
        for (i, scalar) in text.enumerated() {
            let decimal = scalar == "." && i > 0 && i < text.count - 1 && isDigit(text[i - 1]) && isDigit(text[i + 1])
            if marks.contains(scalar) && !decimal {
                parts.append(Array(text[start ... i]))
                start = i + 1
            }
        }
        if start < text.count { parts.append(Array(text[start...])) }
        return parts
    }

    /// Pieces of at most `limit` bytes, cut at the first kind of mark that helps.
    static func fit(_ text: [Unicode.Scalar], limit: Int, marks: [Set<Unicode.Scalar>]) -> [[Unicode.Scalar]] {
        if bytes(text) <= limit { return [text] }
        if let first = marks.first {
            return cutAfter(text, marks: first).flatMap { fit($0, limit: limit, marks: Array(marks.dropFirst())) }
        }
        var pieces: [[Unicode.Scalar]] = []
        var current: [Unicode.Scalar] = []
        var size = 0
        for scalar in text {
            let width = String(scalar).utf8.count
            if !current.isEmpty && size + width > limit {
                pieces.append(current)
                current = []
                size = 0
            }
            current.append(scalar)
            size += width
        }
        return pieces + [current]
    }

    // MARK: - Helpers

    static func bytes(_ scalars: [Unicode.Scalar]) -> Int {
        scalars.reduce(0) { $0 + String($1).utf8.count }
    }

    static func string<S: Sequence>(_ scalars: S) -> String where S.Element == Unicode.Scalar {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    /// Python's `str.isdigit()`: decimal and digit numeric types.
    static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.numericType == .decimal || scalar.properties.numericType == .digit
    }
}
