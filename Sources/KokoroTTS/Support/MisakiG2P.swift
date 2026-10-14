//
//  MisakiG2P.swift
//  KokoroTTS
//
//  Created by David Sherlock on 2026.
//
//  Words to Kokoro's phonemes the way Kokoro's own front end does it.
//
//  A port of the English half of Misaki (hexgrad/misaki 0.9.4, `en.py`,
//  Apache-2.0): dictionary lookup with Misaki's stress rules, its special
//  cases for the words whose sound depends on the next one ("the" before a
//  vowel, "to", "a", "an", "in"), and its -s, -ed and -ing endings built from
//  a known stem. What Misaki gets from spaCy's tagger is guessed from the
//  word before ("to live" is a verb, "had read" a past participle) — enough
//  for the handful of words the lexicon spells by part of speech.
//
//  Why this exists: FluidAudio sends every word through a small neural G2P
//  instead, which reads "is" as "ice" and "this" as "thighs" every time. A
//  bake-off measured 14–26 % word error on plain prose through it, and 0.9 %
//  through Misaki's own phonemes on the same CoreML model.
//
//  Words neither lexicon knows — mostly names — are returned as unknown, so
//  the caller can ask a fallback (the neural G2P, which is fine at names).
//

import Foundation
import SpeechSynthesizer

/// Text to Kokoro phonemes through Misaki's lexicon and rules.
struct MisakiG2P: Sendable {

    let lexicon: MisakiLexicon

    // MARK: - Symbol classes (Misaki's)

    static let primary: Character = "ˈ"
    static let secondary: Character = "ˌ"
    static let vowels = Set("AIOQWYaiuæɑɒɔəɛɜɪʊʌᵻ")
    static let consonants = Set("bdfhjklmnpstvwzðŋɡɹɾʃʒʤʧθ")
    static let punctuation = Set(";:,.!?—…\"“”")
    static let nonQuotePunctuation = Set(";:,.!?—…")
    static let usTaus = Set("AIOWYiuæɑəɛɪɹʊʌ")
    static let symbols = ["%": "percent", "&": "and", "+": "plus", "@": "at"]

    /// What comes after the word being read: whether it starts with a vowel
    /// (`nil` at the end of a phrase) and whether it is "to".
    struct Context: Sendable {
        var futureVowel: Bool?
        var futureTo = false
    }

    /// The result of reading a text.
    struct Reading: Sendable {
        /// The phonemes, words separated by spaces, punctuation kept.
        let phonemes: String
        /// Words the lexicon could not read and no guess was given for.
        let unknown: [String]
    }

    // MARK: - Reading a text

    /// `text` as phonemes. `guesses` supplies phonemes for words the
    /// lexicon does not know, keyed by ``guessKey(_:)``.
    func read(_ text: String, guesses: [String: String] = [:]) -> Reading {
        var tokens = Self.tokens(Self.spellDigits(text))
        if Self.isShouting(tokens) {
            tokens = tokens.map { token in
                var lowered = token
                if token.kind == .word { lowered.text = token.text.lowercased() }
                return lowered
            }
        }

        var context = Context()
        var phonemes = [String?](repeating: nil, count: tokens.count)
        var unknown: [String] = []
        for index in tokens.indices.reversed() {
            let token = tokens[index]
            switch token.kind {
            case .punctuation:
                phonemes[index] = Self.punctuationPhonemes(token, tokens: tokens, at: index)
            case .joiner:
                phonemes[index] = ""
            case .word:
                let tag = Self.guessTag(tokens, before: index)
                if let found = word(token.text, tag: tag, context: context) {
                    phonemes[index] = found
                } else if let guess = guesses[Self.guessKey(token.text)] {
                    phonemes[index] = guess
                } else {
                    unknown.append(token.text)
                }
            }
            context = Self.context(after: context, phonemes: phonemes[index], token: token)
        }

        var result = ""
        for (index, token) in tokens.enumerated() {
            result += phonemes[index] ?? ""
            // "p.m." swallows the sentence's own full stop; give the pause back
            // when the next word starts a sentence.
            if Self.endsSentence(tokens, at: index) { result += "." }
            if token.space || token.kind == .joiner { result += " " }
        }
        // Kokoro 1.0 was trained on Misaki's v1 symbols: flap and glottal
        // stop written as T and t (en.py, `version != '2.0'`).
        result = result.replacingOccurrences(of: "ɾ", with: "T").replacingOccurrences(of: "ʔ", with: "t")
        let collapsed = result.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return Reading(phonemes: collapsed, unknown: unknown.reversed())
    }

    /// The key a fallback guess is stored under: lower case, accents off.
    static func guessKey(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "’", with: "'")
    }

    // MARK: - One word

    /// One word's phonemes in this context, or `nil` if the lexicon cannot read it.
    func word(_ text: String, tag: String?, context: Context) -> String? {
        var word = text.replacingOccurrences(of: "‘", with: "'").replacingOccurrences(of: "’", with: "'")
        word = word.precomposedStringWithCompatibilityMapping
        if let found = wordAsWritten(word, tag: tag, context: context) { return found }
        // Accents the lexicon does not carry: "Reykjavík" → "Reykjavik".
        let folded = word.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
        return folded == word ? nil : wordAsWritten(folded, tag: tag, context: context)
    }

    private func wordAsWritten(_ word: String, tag: String?, context: Context) -> String? {
        let stress: Double? = word == word.lowercased() ? nil : (word == word.uppercased() ? 2 : 0.5)
        return getWord(word, tag: tag, stress: stress, context: context)
    }

    func getWord(_ text: String, tag: String?, stress: Double?, context: Context) -> String? {
        if let special = specialCase(text, tag: tag, stress: stress, context: context) { return special }
        var word = text
        let lower = word.lowercased()
        if word.count > 1, word.replacingOccurrences(of: "'", with: "").allSatisfy(\.isLetter), word != lower,
           tag != "NNP" || word.count > 7, gold(word) == nil, silver(word) == nil,
           word == word.uppercased() || word.dropFirst() == word.dropFirst().lowercased(),
           gold(lower) != nil || silver(lower) != nil
            || stemS(lower, tag: tag, stress: stress, context: context) != nil
            || stemED(lower, tag: tag, stress: stress, context: context) != nil
            || stemING(lower, tag: tag, stress: stress, context: context) != nil {
            word = lower
        }
        if isKnown(word, tag: tag) { return lookup(word, tag: tag, stress: stress, context: context) }
        if word.hasSuffix("s'"), isKnown(String(word.dropLast(2)) + "'s", tag: tag) {
            return lookup(String(word.dropLast(2)) + "'s", tag: tag, stress: stress, context: context)
        }
        if word.hasSuffix("'"), isKnown(String(word.dropLast()), tag: tag) {
            return lookup(String(word.dropLast()), tag: tag, stress: stress, context: context)
        }
        if let found = stemS(word, tag: tag, stress: stress, context: context) { return found }
        if let found = stemED(word, tag: tag, stress: stress, context: context) { return found }
        return stemING(word, tag: tag, stress: stress ?? 0.5, context: context)
    }

    /// Misaki's words whose sound depends on context, not the dictionary.
    func specialCase(_ word: String, tag: String?, stress: Double?, context: Context) -> String? {
        if let name = Self.symbols[word] { return lookup(name, tag: nil, stress: nil, context: context) }
        let inner = word.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let parts = word.split(separator: ".", omittingEmptySubsequences: false)
        if inner.contains("."), word.replacingOccurrences(of: ".", with: "").allSatisfy(\.isLetter),
           (parts.map(\.count).max() ?? 0) < 3 {
            return properNoun(word)
        }
        switch word {
        case "a", "A":
            // Misaki: "ɐ" for the article, "ˈA" for the letter. Untagged, the
            // letter is the one standing alone before a pause.
            return word == "A" && context.futureVowel == nil ? "ˈA" : "ɐ"
        case "am", "Am", "AM":
            if context.futureVowel == nil || word != "am" || (stress ?? 0) > 0 { return plain(gold("am")) }
            return "ɐm"
        case "an", "An", "AN":
            return "ɐn"
        case "I":
            return "\(Self.secondary)I"
        case "to", "To", "TO":
            switch context.futureVowel {
            case nil: return plain(gold("to"))
            case false?: return "tə"
            case true?: return "tʊ"
            }
        case "in", "In", "IN":
            return (context.futureVowel == nil ? String(Self.primary) : "") + "ɪn"
        case "the", "The", "THE":
            return context.futureVowel == true ? "ði" : "ðə"
        case "used", "Used", "USED":
            if case .tagged(let spellings)? = gold("used") {
                let key = (tag == "VBD" || tag == "JJ") && context.futureTo ? "VBD" : "DEFAULT"
                return spellings[key] ?? nil
            }
            return nil
        default:
            return nil
        }
    }

    /// Misaki's `lookup`: gold, then silver, the tag's spelling, then stress.
    func lookup(_ text: String, tag: String?, stress: Double?, context: Context?) -> String? {
        var word = text
        var properNoun = false
        if word == word.uppercased(), gold(word) == nil {
            word = word.lowercased()
            properNoun = tag == "NNP"
        }
        var entry = gold(word)
        if entry == nil && !properNoun { entry = silver(word) }
        var phonemes: String?
        switch entry {
        case .plain(let spelling)?:
            phonemes = spelling
        case .tagged(let spellings)?:
            // Python's `ps.get(tag, ps['DEFAULT'])`: a tag that is present
            // wins even when its spelling is null ("spell it out").
            var key = tag
            if let context, context.futureVowel == nil, spellings.keys.contains("None") {
                key = "None"
            } else if key.map({ !spellings.keys.contains($0) }) ?? true {
                key = Self.parentTag(tag)
            }
            if let key, let spelling = spellings[key] {
                phonemes = spelling
            } else {
                phonemes = spellings["DEFAULT"] ?? nil
            }
        case nil:
            phonemes = nil
        }
        if phonemes == nil || (properNoun && !(phonemes?.contains(Self.primary) ?? false)) {
            if let spelled = self.properNoun(word) { return spelled }
        }
        return phonemes.map { Self.applyStress($0, stress) }
    }

    /// A word read letter by letter: "NHS" → "ˌɛnˌAʧˈɛs".
    func properNoun(_ word: String) -> String? {
        var letters = ""
        for character in word where character.isLetter {
            guard let spelled = plain(gold(String(character).uppercased())) else { return nil }
            letters += spelled
        }
        guard !letters.isEmpty else { return nil }
        let stressed = Self.applyStress(letters, 0)
        guard let last = stressed.lastIndex(of: Self.secondary) else { return stressed }
        return String(stressed[..<last]) + String(Self.primary) + String(stressed[stressed.index(after: last)...])
    }

    func isKnown(_ word: String, tag: String?) -> Bool {
        if gold(word) != nil || Self.symbols[word] != nil || silver(word) != nil { return true }
        guard word.allSatisfy(\.isLetter), word.unicodeScalars.allSatisfy(Self.isLexiconScalar) else { return false }
        if word.count == 1 { return true }
        if word == word.uppercased(), gold(word.lowercased()) != nil { return true }
        return word.dropFirst() == word.dropFirst().uppercased()
    }

    /// Misaki's `LEXICON_ORDS`: apostrophe, hyphen and ASCII letters.
    static func isLexiconScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "'" || scalar == "-" || ("A"..."Z").contains(scalar) || ("a"..."z").contains(scalar)
    }

    // MARK: - Endings built on a known stem

    func stemS(_ word: String, tag: String?, stress: Double?, context: Context?) -> String? {
        guard word.count >= 3, word.hasSuffix("s") else { return nil }
        let stem: String
        if !word.hasSuffix("ss"), isKnown(String(word.dropLast()), tag: tag) {
            stem = String(word.dropLast())
        } else if (word.hasSuffix("'s") || (word.count > 4 && word.hasSuffix("es") && !word.hasSuffix("ies"))),
                  isKnown(String(word.dropLast(2)), tag: tag) {
            stem = String(word.dropLast(2))
        } else if word.count > 4, word.hasSuffix("ies"), isKnown(String(word.dropLast(3)) + "y", tag: tag) {
            stem = String(word.dropLast(3)) + "y"
        } else {
            return nil
        }
        return lookup(stem, tag: tag, stress: stress, context: context).flatMap(suffixS)
    }

    func suffixS(_ stem: String) -> String? {
        guard let last = stem.last else { return nil }
        if "ptkfθ".contains(last) { return stem + "s" }
        if "szʃʒʧʤ".contains(last) { return stem + (lexicon.british ? "ɪ" : "ᵻ") + "z" }
        return stem + "z"
    }

    func stemED(_ word: String, tag: String?, stress: Double?, context: Context?) -> String? {
        guard word.count >= 4, word.hasSuffix("d") else { return nil }
        let stem: String
        if !word.hasSuffix("dd"), isKnown(String(word.dropLast()), tag: tag) {
            stem = String(word.dropLast())
        } else if word.count > 4, word.hasSuffix("ed"), !word.hasSuffix("eed"), isKnown(String(word.dropLast(2)), tag: tag) {
            stem = String(word.dropLast(2))
        } else {
            return nil
        }
        return lookup(stem, tag: tag, stress: stress, context: context).flatMap(suffixED)
    }

    func suffixED(_ stem: String) -> String? {
        guard let last = stem.last else { return nil }
        if "pkfθʃsʧ".contains(last) { return stem + "t" }
        if last == "d" { return stem + (lexicon.british ? "ɪ" : "ᵻ") + "d" }
        if last != "t" { return stem + "d" }
        if lexicon.british || stem.count < 2 { return stem + "ɪd" }
        let beforeLast = stem[stem.index(stem.endIndex, offsetBy: -2)]
        if Self.usTaus.contains(beforeLast) { return String(stem.dropLast()) + "ɾᵻd" }
        return stem + "ᵻd"
    }

    func stemING(_ word: String, tag: String?, stress: Double?, context: Context?) -> String? {
        guard word.count >= 5, word.hasSuffix("ing") else { return nil }
        let base = String(word.dropLast(3))
        let stem: String
        if word.count > 5, isKnown(base, tag: tag) {
            stem = base
        } else if isKnown(base + "e", tag: tag) {
            stem = base + "e"
        } else if word.count > 5, Self.doubledConsonantING(word), isKnown(String(word.dropLast(4)), tag: tag) {
            stem = String(word.dropLast(4))
        } else {
            return nil
        }
        return lookup(stem, tag: tag, stress: stress, context: context).flatMap(suffixING)
    }

    /// `([bcdgklmnprstvxz])\1ing$|cking$` — "running", "packing".
    static func doubledConsonantING(_ word: String) -> Bool {
        if word.hasSuffix("cking") { return true }
        let letters = Array(word.dropLast(3))
        guard letters.count >= 2, let last = letters.last else { return false }
        return letters[letters.count - 2] == last && "bcdgklmnprstvxz".contains(last)
    }

    func suffixING(_ stem: String) -> String? {
        guard let last = stem.last else { return nil }
        if lexicon.british {
            if "əː".contains(last) { return nil }
        } else if stem.count > 1, last == "t", Self.usTaus.contains(stem[stem.index(stem.endIndex, offsetBy: -2)]) {
            return String(stem.dropLast()) + "ɾɪŋ"
        }
        return stem + "ɪŋ"
    }

    // MARK: - Lexicon access (Misaki's grown dictionary)

    /// The entry for `word`, where "Farmers" also finds "farmers" and
    /// "maya" also finds "Maya" — Misaki's `grow_dictionary`.
    func gold(_ word: String) -> MisakiLexicon.Entry? { Self.entry(word, in: lexicon.gold) }
    func silver(_ word: String) -> MisakiLexicon.Entry? { Self.entry(word, in: lexicon.silver) }

    static func entry(_ word: String, in table: [String: MisakiLexicon.Entry]) -> MisakiLexicon.Entry? {
        if let found = table[word] { return found }
        guard word.count >= 2 else { return nil }
        let lower = word.lowercased()
        if word == capitalized(lower), let found = table[lower] { return found }
        if word == lower, let found = table[capitalized(lower)], capitalized(lower) != lower { return found }
        return nil
    }

    /// Python's `str.capitalize()`: first letter up, the rest down.
    static func capitalized(_ word: String) -> String {
        guard let first = word.first else { return word }
        return first.uppercased() + word.dropFirst().lowercased()
    }

    func plain(_ entry: MisakiLexicon.Entry?) -> String? {
        switch entry {
        case .plain(let spelling)?: return spelling
        case .tagged(let spellings)?: return spellings["DEFAULT"] ?? nil
        case nil: return nil
        }
    }

    static func parentTag(_ tag: String?) -> String? {
        guard let tag else { return nil }
        if tag.hasPrefix("VB") { return "VERB" }
        if tag.hasPrefix("NN") { return "NOUN" }
        if tag.hasPrefix("ADV") || tag.hasPrefix("RB") { return "ADV" }
        if tag.hasPrefix("ADJ") || tag.hasPrefix("JJ") { return "ADJ" }
        return tag
    }

    // MARK: - Stress (Misaki's apply_stress)

    static func applyStress(_ phonemes: String, _ stress: Double?) -> String {
        guard let stress else { return phonemes }
        let hasPrimary = phonemes.contains(primary), hasSecondary = phonemes.contains(secondary)
        let hasVowel = phonemes.contains { vowels.contains($0) }
        if stress < -1 {
            return phonemes.filter { $0 != primary && $0 != secondary }
        } else if stress == -1 || ((stress == 0 || stress == -0.5) && hasPrimary) {
            return String(phonemes.filter { $0 != secondary }.map { $0 == primary ? secondary : $0 })
        } else if [0, 0.5, 1].contains(stress) && !hasPrimary && !hasSecondary {
            return hasVowel ? restress(String(secondary) + phonemes) : phonemes
        } else if stress >= 1 && !hasPrimary && hasSecondary {
            return String(phonemes.map { $0 == secondary ? primary : $0 })
        } else if stress > 1 && !hasPrimary && !hasSecondary {
            return hasVowel ? restress(String(primary) + phonemes) : phonemes
        }
        return phonemes
    }

    /// Moves each stress mark to just before the vowel it belongs to.
    static func restress(_ phonemes: String) -> String {
        let characters = Array(phonemes)
        var placed = characters.enumerated().map { (position: Double($0.offset), character: $0.element) }
        for (index, character) in characters.enumerated() where character == primary || character == secondary {
            if let vowel = characters[index...].firstIndex(where: { vowels.contains($0) }) {
                placed[index].position = Double(vowel) - 0.5
            }
        }
        return String(placed.sorted { $0.position < $1.position }.map(\.character))
    }

    // MARK: - Tokens

    struct Token: Sendable, Equatable {
        enum Kind: Sendable { case word, punctuation, joiner }
        var text: String
        var kind: Kind
        /// Whitespace follows.
        var space: Bool
    }

    /// Words (with inner apostrophes, or dotted like "p.m."), single
    /// punctuation marks, and the hyphen that joins two words.
    static func tokens(_ text: String) -> [Token] {
        let pattern = #"(?:\p{L}\.){2,}|[\p{L}\p{M}]+(?:['’][\p{L}\p{M}]+)*|\S"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = text as NSString
        var tokens: [Token] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let piece = source.substring(with: match.range)
            let end = match.range.location + match.range.length
            let space = end < source.length && source.substring(with: NSRange(location: end, length: 1))
                .unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains)
            let isWord = piece.first.map { $0.isLetter } ?? false
            var kind: Token.Kind = isWord ? .word : .punctuation
            // A hyphen with a word on each side joins them: "street-lamps".
            if (piece == "-" || piece == "‐") && !space, let previous = tokens.last, previous.kind == .word,
               !previous.space {
                kind = .joiner
            }
            tokens.append(Token(text: piece, kind: kind, space: space))
        }
        return tokens
    }

    /// The phonemes a mark stands for: itself if Kokoro knows it, a dash
    /// for a spaced hyphen, nothing otherwise.
    static func punctuationPhonemes(_ token: Token, tokens: [Token], at index: Int) -> String {
        let mark = token.text
        // Straight quotes become the curly ones Misaki's tagger produces
        // (`` and ''): opening after a space or at the start, closing otherwise.
        if mark == "\"" {
            let opens = index == 0 || tokens[index - 1].space || tokens[index - 1].text == "("
            return opens ? "“" : "”"
        }
        if mark.count == 1, let character = mark.first, punctuation.contains(character) { return mark }
        if mark == "(" || mark == ")" { return mark }
        if mark == "-" || mark == "–" { return "—" }
        return ""
    }

    /// Misaki's `token_context`: what the reader is about to say next.
    static func context(after context: Context, phonemes: String?, token: Token) -> Context {
        var vowel = context.futureVowel
        if let phonemes, !phonemes.isEmpty {
            for character in phonemes
            where vowels.contains(character) || consonants.contains(character) || nonQuotePunctuation.contains(character) {
                vowel = nonQuotePunctuation.contains(character) ? nil : vowels.contains(character)
                break
            }
        }
        let futureTo = ["to", "To", "TO"].contains(token.text)
        return Context(futureVowel: vowel, futureTo: futureTo)
    }

    /// A part of speech from the word before, for the few words the lexicon
    /// spells by tag. `NNP` for an acronym, so "US" and "IT" are spelled.
    static func guessTag(_ tokens: [Token], before index: Int) -> String? {
        let word = tokens[index].text
        if word.count >= 2, word == word.uppercased(), word != word.lowercased() { return "NNP" }
        var previousIndex = index - 1
        while previousIndex >= 0, tokens[previousIndex].kind == .joiner { previousIndex -= 1 }
        guard previousIndex >= 0, tokens[previousIndex].kind == .word else { return nil }
        let previous = tokens[previousIndex].text.lowercased().replacingOccurrences(of: "’", with: "'")
        if verbCues.contains(previous) { return "VB" }
        if nounCues.contains(previous) || NumberWords.isNumberWord(previous) { return "NN" }
        if participleCues.contains(previous) { return "VBN" }
        return nil
    }

    /// Words after which the next is read as a verb. The pronouns are for
    /// the lexicon's noun/verb pairs: "we live", "most of us live".
    static let verbCues: Set<String> = [
        "i", "you", "we", "they", "he", "she", "who", "us",
        "to", "will", "would", "can", "could", "should", "must", "might", "may", "shall", "do", "does", "did",
        "don't", "doesn't", "didn't", "won't", "can't", "cannot", "couldn't", "wouldn't", "shouldn't", "let's",
        "i'll", "we'll", "you'll", "they'll", "he'll", "she'll", "i'd", "we'd", "you'd", "they'd",
    ]

    /// Determiners: what follows is read as a noun ("the estimate", "a refund").
    static let nounCues: Set<String> = [
        "the", "a", "an", "this", "that", "these", "those", "my", "your", "his", "her", "its", "our", "their",
        "no", "every", "each", "some", "any",
    ]

    static let participleCues: Set<String> = [
        "have", "has", "had", "having", "been", "i've", "we've", "you've", "they've", "haven't", "hasn't", "hadn't",
    ]

    /// A dotted abbreviation ("p.m.", "U.S.") last in the text or before a
    /// capitalised word, where its final dot is also a full stop.
    static func endsSentence(_ tokens: [Token], at index: Int) -> Bool {
        let token = tokens[index]
        guard token.kind == .word, token.text.hasSuffix("."), token.text.count > 2 else { return false }
        guard index + 1 < tokens.count else { return true }
        let next = tokens[index + 1]
        return next.kind == .word && (next.text.first?.isUppercase ?? false)
    }

    /// Mostly capitals is shouting, not acronyms: read the words.
    static func isShouting(_ tokens: [Token]) -> Bool {
        let words = tokens.filter { $0.kind == .word && $0.text.count >= 2 }
        guard words.count >= 3 else { return false }
        let capitals = words.filter { $0.text == $0.text.uppercased() && $0.text != $0.text.lowercased() }.count
        return Double(capitals) / Double(words.count) >= 0.6
    }

    /// Digits the normaliser left behind, as words.
    static func spellDigits(_ text: String) -> String {
        guard text.contains(where: \.isNumber) else { return text }
        return SpokenText.normalize(text)
    }
}
