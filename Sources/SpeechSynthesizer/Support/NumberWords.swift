//
//  NumberWords.swift
//  SpeechSynthesizer
//
//  Created by David Sherlock on 2026.
//
//  Numbers as an English reader says them. Pure functions: no locale, no
//  Foundation formatter (NumberFormatter's spell-out style says "two
//  thousand twenty-six" for a year and has no "oh" for 9:05).
//

import Foundation

/// Spelling numbers out in English words.
public enum NumberWords {

    static let ones = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
    ]

    static let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    static let scales: [(value: Int, name: String)] = [
        (1_000_000_000_000, "trillion"), (1_000_000_000, "billion"), (1_000_000, "million"), (1_000, "thousand"),
    ]

    /// `1250` → "one thousand two hundred fifty". No "and", the way a US
    /// reader and Kokoro's own reference front end (Misaki) both say it.
    public static func cardinal(_ number: Int) -> String {
        if number < 0 { return "minus " + cardinal(-number) }
        if number < 20 { return ones[number] }
        if number < 100 {
            let unit = number % 10
            return tens[number / 10] + (unit == 0 ? "" : "-" + ones[unit])
        }
        if number < 1000 {
            let rest = number % 100
            return ones[number / 100] + " hundred" + (rest == 0 ? "" : " " + cardinal(rest))
        }
        for scale in scales where number >= scale.value {
            let rest = number % scale.value
            return cardinal(number / scale.value) + " " + scale.name + (rest == 0 ? "" : " " + cardinal(rest))
        }
        return digits(String(number))
    }

    /// `21` → "twenty-first".
    public static func ordinal(_ number: Int) -> String {
        let words = cardinal(number)
        // Only the last word changes: "one hundred twenty-one" → "…twenty-first".
        let cut = words.lastIndex { $0 == " " || $0 == "-" }.map { words.index(after: $0) } ?? words.startIndex
        return String(words[..<cut]) + ordinalWord(String(words[cut...]))
    }

    static func ordinalWord(_ word: String) -> String {
        switch word {
        case "one": return "first"
        case "two": return "second"
        case "three": return "third"
        case "five": return "fifth"
        case "eight": return "eighth"
        case "nine": return "ninth"
        case "twelve": return "twelfth"
        default:
            return word.hasSuffix("y") ? String(word.dropLast()) + "ieth" : word + "th"
        }
    }

    /// A year as it is read: 2026 → "twenty twenty-six", 1905 → "nineteen
    /// oh five", 1900 → "nineteen hundred", 2005 → "two thousand five".
    public static func year(_ number: Int) -> String {
        guard (1000...9999).contains(number) else { return cardinal(number) }
        if number % 1000 == 0 || (2000...2009).contains(number) { return cardinal(number) }
        let high = number / 100, low = number % 100
        if low == 0 { return cardinal(high) + " hundred" }
        return cardinal(high) + " " + (low < 10 ? "oh " + ones[low] : cardinal(low))
    }

    /// Each digit on its own: "0447" → "zero four four seven".
    public static func digits(_ text: some StringProtocol) -> String {
        text.compactMap { $0.wholeNumberValue }.map { ones[$0] }.joined(separator: " ")
    }

    /// A decimal: "3.14" → "three point one four", "1,250.5" → "one
    /// thousand two hundred fifty point five", ".5" → "point five".
    public static func decimal(_ text: String) -> String {
        let plain = text.replacingOccurrences(of: ",", with: "")
        let parts = plain.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let whole = parts.first.map(String.init) ?? ""
        var words = whole.isEmpty ? "" : integer(whole)
        if parts.count == 2, !parts[1].isEmpty {
            words += (words.isEmpty ? "" : " ") + "point " + digits(parts[1])
        }
        return words
    }

    /// Digits as one number, or digit by digit when that is how they are
    /// read: a leading zero ("007") or more digits than any scale names.
    static func integer(_ text: some StringProtocol) -> String {
        let plain = String(text.filter(\.isNumber))
        if plain.count > 1 && plain.hasPrefix("0") { return digits(plain) }
        guard plain.count <= 15, let value = Int(plain) else { return digits(plain) }
        return cardinal(value)
    }

    /// Whether `word` is one of the words numbers are spelled with
    /// ("five", "twenty-five", "hundred", "fifth").
    public static func isNumberWord(_ word: String) -> Bool {
        let parts = word.lowercased().split(separator: "-").map(String.init)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { part in
            ones.contains(part) || tens.contains(part) && !part.isEmpty || scales.contains { $0.name == part }
                || part == "hundred" || (1...19).contains { ordinalWord(ones[$0]) == part }
                || tens.dropFirst(2).contains { ordinalWord($0) == part }
        }
    }

    /// `1` + "dollar" → "one dollar"; any other amount takes the plural.
    static func counted(_ amount: Int, _ singular: String, _ plural: String) -> String {
        cardinal(amount) + " " + (amount == 1 ? singular : plural)
    }

    /// A word for a decade's plural: "ninety" → "nineties", "ten" → "tens".
    static func plural(_ words: String) -> String {
        if words.hasSuffix("y") { return String(words.dropLast()) + "ies" }
        return words + "s"
    }

    /// `3`/`4` → "three quarters"; `1`/`2` → "one half"; other denominators
    /// over ten are read "x over y".
    public static func fraction(_ numerator: Int, _ denominator: Int) -> String {
        let named: (String, String)? = switch denominator {
        case 2: ("half", "halves")
        case 4: ("quarter", "quarters")
        case 3, 5, 6, 7, 8, 9, 10: (ordinal(denominator), ordinal(denominator) + "s")
        default: nil
        }
        guard let named, denominator != 0 else { return cardinal(numerator) + " over " + cardinal(denominator) }
        return cardinal(numerator) + " " + (numerator == 1 ? named.0 : named.1)
    }
}
