//
//  VoiceDesignVocabulary.swift
//  OmniVoiceTTS
//
//  Created by David Sherlock on 2026.
//
//  OmniVoice designs a voice from a closed vocabulary, not from a description:
//  one word or phrase per category (gender, age, pitch, style, English accent,
//  Chinese dialect), comma-separated. Anything else — "warm", "older",
//  "cheerful" — is refused by the reference implementation, and passed
//  silently to the model by the MLX ports, which then ignores it or worse.
//  This is the reference's own `_resolve_instruct` (k2-fsa/OmniVoice,
//  omnivoice/utils/voice_design.py + models/omnivoice.py, Apache-2.0), ported.
//

import Foundation

/// The words OmniVoice's voice design understands, and the check that keeps
/// everything else out.
public enum VoiceDesignVocabulary {

    /// One category: its name and its items, English → Chinese where both exist.
    struct Category: Sendable {
        let name: String
        let pairs: [(english: String, chinese: String)]
        let englishOnly: [String]
        let chineseOnly: [String]

        var all: [String] { pairs.flatMap { [$0.english, $0.chinese] } + englishOnly + chineseOnly }
    }

    static let categories: [Category] = [
        Category(name: "gender", pairs: [("male", "男"), ("female", "女")], englishOnly: [], chineseOnly: []),
        Category(name: "age", pairs: [("child", "儿童"), ("teenager", "少年"), ("young adult", "青年"),
                                      ("middle-aged", "中年"), ("elderly", "老年")],
                 englishOnly: [], chineseOnly: []),
        Category(name: "pitch", pairs: [("very low pitch", "极低音调"), ("low pitch", "低音调"),
                                        ("moderate pitch", "中音调"), ("high pitch", "高音调"),
                                        ("very high pitch", "极高音调")],
                 englishOnly: [], chineseOnly: []),
        Category(name: "style", pairs: [("whisper", "耳语")], englishOnly: [], chineseOnly: []),
        Category(name: "accent", pairs: [],
                 englishOnly: ["american accent", "british accent", "australian accent", "canadian accent",
                               "indian accent", "chinese accent", "korean accent", "japanese accent",
                               "portuguese accent", "russian accent"],
                 chineseOnly: []),
        Category(name: "dialect", pairs: [], englishOnly: [],
                 chineseOnly: ["河南话", "陕西话", "四川话", "贵州话", "云南话", "桂林话", "济南话", "石家庄话",
                               "甘肃话", "宁夏话", "青岛话", "东北话"]),
    ]

    /// Every accepted item, English and Chinese.
    public static let allItems: Set<String> = Set(categories.flatMap(\.all))

    /// The English items, grouped by category, for help and error text.
    public static var englishItemsByCategory: [(category: String, items: [String])] {
        categories.compactMap { category in
            let items = category.pairs.map(\.english) + category.englishOnly
            return items.isEmpty ? nil : (category.name, items)
        }
    }

    /// The vocabulary as one line per category: `gender: male, female`.
    public static var summary: String {
        englishItemsByCategory.map { "\($0.category): \($0.items.joined(separator: ", "))" }.joined(separator: "\n")
            + "\ndialect (Chinese text only): "
            + (categories.last?.chineseOnly.joined(separator: "、") ?? "")
    }

    private static let englishToChinese: [String: String] = Dictionary(
        uniqueKeysWithValues: categories.flatMap(\.pairs).map { ($0.english, $0.chinese) })
    private static let chineseToEnglish: [String: String] = Dictionary(
        uniqueKeysWithValues: categories.flatMap(\.pairs).map { ($0.chinese, $0.english) })

    /// Validates a voice design and returns it in the form the model was
    /// trained on: lower-cased, one language throughout, the right separator.
    ///
    /// - Parameters:
    ///   - design: Comma-separated items, e.g. `"male, elderly, low pitch, british accent"`.
    ///   - text: The text to be spoken — Chinese text turns the items Chinese
    ///     unless an English accent is named, as the reference does.
    /// - Returns: The normalised design, or nil for an empty one.
    /// - Throws: ``OmniVoiceError/invalidVoiceDesign(_:)`` naming each unknown
    ///   item (with the closest valid one), or a clash within a category.
    public static func resolve(_ design: String, text: String = "") throws(OmniVoiceError) -> String? {
        let raw = design.split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !raw.isEmpty else { return nil }

        var items: [String] = []
        var unknown: [String] = []
        for item in raw {
            let lowered = item.lowercased()
            if allItems.contains(lowered) {
                items.append(lowered)
            } else if let suggestion = closest(to: lowered) {
                unknown.append("'\(item)' (did you mean '\(suggestion)'?)")
            } else {
                unknown.append("'\(item)'")
            }
        }
        if !unknown.isEmpty {
            throw .invalidVoiceDesign(
                "Voice design takes only fixed words, one per category; not "
                + unknown.joined(separator: ", ") + ".\n" + summary)
        }

        let hasDialect = items.contains { $0.hasSuffix("话") }
        let hasAccent = items.contains { $0.contains(" accent") }
        if hasDialect && hasAccent {
            throw .invalidVoiceDesign("An English accent and a Chinese dialect cannot be combined: "
                                      + "accents apply to English speech, dialects to Chinese.")
        }
        let chinese = hasDialect || (!hasAccent && containsHan(text))
        items = items.map { chinese ? (englishToChinese[$0] ?? $0) : (chineseToEnglish[$0] ?? $0) }

        for category in categories {
            let members = Set(category.all)
            let hits = items.filter { members.contains($0) }
            if hits.count > 1 {
                throw .invalidVoiceDesign("Pick one \(category.name), not "
                                          + hits.map { "'\($0)'" }.joined(separator: " and ") + ".")
            }
        }
        return items.joined(separator: items.contains(where: containsHan) ? "，" : ", ")
    }

    /// Whether `text` has CJK unified ideographs, the reference's test for Chinese.
    static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    /// The valid item nearest to `item`, when it is close enough to be a typo
    /// (similarity ≥ 0.6, as `difflib.get_close_matches` uses).
    static func closest(to item: String) -> String? {
        var best: (item: String, score: Double)?
        for candidate in allItems {
            let score = similarity(item, candidate)
            if score >= 0.6, score > (best?.score ?? 0) { best = (candidate, score) }
        }
        return best?.item
    }

    /// 1 − normalised edit distance.
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(a), y = Array(b)
        guard !x.isEmpty || !y.isEmpty else { return 1 }
        var previous = Array(0...y.count)
        for i in 1...max(1, x.count) where !x.isEmpty {
            var current = [i] + Array(repeating: 0, count: y.count)
            for j in 1...max(1, y.count) where !y.isEmpty {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return 1 - Double(previous[y.count]) / Double(max(x.count, y.count))
    }
}
