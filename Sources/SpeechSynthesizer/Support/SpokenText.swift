//
//  SpokenText.swift
//  SpeechSynthesizer
//
//  Created by David Sherlock on 2026.
//
//  Text as it is read aloud, before it reaches a model.
//
//  Neural voices are trained on words. Hand Kokoro "$1,250.50" and its
//  front end has nothing to look up, so a voice bake-off heard "x" for
//  nearly every digit (1 of 11 number items right). This writes the words
//  out first — numbers, ordinals, years, dates, times, money, percentages,
//  decimals, ranges, units, phone numbers and the common abbreviations —
//  as a pure function every engine can share.
//
//  The rules run in order, most specific first: a phone number before a
//  range, a date before a year, money before a plain number. Each leaves
//  words behind, so a later rule never sees what an earlier one handled.
//

import Foundation

/// Rewrites text into the words a reader would say.
public enum SpokenText {

    /// `text` with numbers, dates, times, money, units and abbreviations
    /// written out as words.
    ///
    /// ```swift
    /// SpokenText.normalize("On 3 Oct 2026 Dr. Smith paid $1,250.50 at 9:45 pm.")
    /// // "On the third of October twenty twenty-six Doctor Smith paid one thousand
    /// //  two hundred fifty dollars and fifty cents at nine forty-five p.m."
    /// ```
    ///
    /// - Parameters:
    ///   - text: Any text; line breaks are kept.
    ///   - language: A BCP-47 tag. Only the order of an all-number date
    ///     depends on it: `en-US` reads 03/10/2026 as March 10, the rest of
    ///     the English-speaking world as 3 October.
    public static func normalize(_ text: String, language: String = "en-US") -> String {
        var text = prepare(text)
        text = phoneNumbers(text)
        text = numericDates(text, monthFirst: language.lowercased().hasPrefix("en-us") || language == "en")
        // Ranges before times ("9:00-17:00" → "… to …"), weekdays before
        // dates (a weekday is spotted by the day number after it).
        text = ranges(text)
        text = weekdays(text)
        text = namedDates(text)
        text = times(text)
        text = money(text)
        text = percentages(text)
        text = decades(text)
        text = units(text)
        text = ordinals(text)
        text = abbreviations(text)
        text = fractions(text)
        text = numbers(text)
        text = symbols(text)
        return tidy(text)
    }

    /// A number as the rules match it: "1,250", "1,250.50", "3.14", "42".
    static let number = #"(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?"#

    // MARK: - Rules

    /// Unicode spaces and the minus sign become their plain forms.
    static func prepare(_ text: String) -> String {
        var result = text
        for (from, to) in [("\u{00A0}", " "), ("\u{2009}", " "), ("\u{202F}", " "), ("\u{2007}", " "),
                           ("\u{2212}", "-"), ("\u{FF04}", "$")] {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result
    }

    /// "+44 20 7946 0958", "(555) 123-4567", "555-123-4567", "07700 900123":
    /// digit by digit, a comma between groups.
    static func phoneNumbers(_ text: String) -> String {
        let patterns = [
            // A bracketed area code.
            #"(?<![\w+])(?:\+\d{1,3}[ .-]?)?\(\d{1,5}\)[ .-]?\d{2,5}(?:[ .-]\d{2,5}){0,2}(?![\w])"#,
            // An international number.
            #"(?<![\w+])\+\d{1,3}(?:[ .-]?\d{1,5}){2,5}(?![\w])"#,
            // North American, with dashes or dots.
            #"(?<![\w.-])\d{3}[-.]\d{3}[-.]\d{4}(?![\w]|[.-]\d)"#,
            // A trunk prefix: 020 7946 0958, 07700 900123, 07700900123.
            #"(?<![\w.,-])0\d{2,4}[ -]\d{3,4}(?:[ -]?\d{3,4})?(?![\w]|[.,]\d)"#,
            #"(?<![\w.,-])0\d{9,10}(?![\w]|[.,]\d)"#,
        ]
        var result = text
        for pattern in patterns {
            result = PatternRewriter.rewrite(result, pattern) { match in
                guard let whole = match[0] else { return nil }
                let digits = whole.filter(\.isNumber)
                guard (9...15).contains(digits.count) else { return nil }
                var groups: [String] = []
                var current = ""
                for character in whole {
                    if character.isNumber {
                        current.append(character)
                    } else if !current.isEmpty {
                        groups.append(current)
                        current = ""
                    }
                }
                if !current.isEmpty { groups.append(current) }
                let spoken = groups.map { NumberWords.digits($0) }.joined(separator: ", ")
                return (whole.hasPrefix("+") ? "plus " : "") + spoken
            }
        }
        return result
    }

    /// "2026-10-03", "10/3/2026", "3/10/26".
    static func numericDates(_ text: String, monthFirst: Bool) -> String {
        var result = PatternRewriter.rewrite(text, #"(?<![\w-])(\d{4})-(\d{1,2})-(\d{1,2})(?![\w-])"#) { match in
            guard let year = match[1].flatMap(Int.init), let month = match[2].flatMap(Int.init),
                  let day = match[3].flatMap(Int.init) else { return nil }
            return monthDay(month, day).map { "\($0), \(NumberWords.year(year))" }
        }
        result = PatternRewriter.rewrite(result, #"(?<![\w/.])(\d{1,2})/(\d{1,2})/(\d{4}|\d{2})(?![\w/])"#) { match in
            guard let first = match[1].flatMap(Int.init), let second = match[2].flatMap(Int.init),
                  let rawYear = match[3], let yearValue = Int(rawYear) else { return nil }
            let year = rawYear.count == 2 ? (yearValue < 50 ? 2000 + yearValue : 1900 + yearValue) : yearValue
            // A value over twelve settles the order whatever the language.
            let readMonthFirst = second > 12 ? true : (first > 12 ? false : monthFirst)
            let (month, day) = readMonthFirst ? (first, second) : (second, first)
            guard (1...12).contains(month), (1...31).contains(day) else { return nil }
            let words = readMonthFirst
                ? "\(SpokenVocabulary.monthNames[month - 1]) \(NumberWords.ordinal(day))"
                : "the \(NumberWords.ordinal(day)) of \(SpokenVocabulary.monthNames[month - 1])"
            return "\(words), \(NumberWords.year(year))"
        }
        return result
    }

    /// "October third", or `nil` for a date that does not exist.
    static func monthDay(_ month: Int, _ day: Int) -> String? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        return "\(SpokenVocabulary.monthNames[month - 1]) \(NumberWords.ordinal(day))"
    }

    /// "3 Oct 2026", "3rd of October", "Oct. 3, 2026", "October 2026".
    static func namedDates(_ text: String) -> String {
        let month = SpokenVocabulary.monthPattern
        // Day first: "3 Oct 2026", "the 3rd of October".
        var result = PatternRewriter.rewrite(
            text, #"(?<![\w.,])(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?"# + month + #"(\.)?(?:,?\s+(\d{4}))?(?![\w])"#
        ) { match in
            guard let day = match[1].flatMap(Int.init), (1...31).contains(day),
                  let name = match[2], let index = SpokenVocabulary.month(name) else { return nil }
            let article = match.before(4).lowercased().hasSuffix("the ") ? "" : "the "
            var words = "\(article)\(NumberWords.ordinal(day)) of \(SpokenVocabulary.monthNames[index - 1])"
            if let year = match[4].flatMap(Int.init) { words += " \(NumberWords.year(year))" }
            if match[3] != nil && match[4] == nil && match.endsSentence { words += "." }
            return words
        }
        // Month first: "Oct 3, 2026", "October 3rd".
        result = PatternRewriter.rewrite(
            result, month + #"(\.)?\s+(\d{1,2})(?:st|nd|rd|th)?(?![\d:.,]\d|\w)(?:,?\s+(\d{4})(?![\w]))?"#
        ) { match in
            guard let name = match[1], let index = SpokenVocabulary.month(name),
                  let day = match[3].flatMap(Int.init), let words = monthDay(index, day) else { return nil }
            guard !shortMonthIsAWord(name, before: match.before(1)) else { return nil }
            return words + (match[4].flatMap(Int.init).map { ", " + NumberWords.year($0) } ?? "")
        }
        // Month and year: "October 2026", "Oct 2026".
        result = PatternRewriter.rewrite(result, month + #"(\.)?\s+(\d{4})(?![\w])"#) { match in
            guard let name = match[1], let index = SpokenVocabulary.month(name),
                  let year = match[3].flatMap(Int.init) else { return nil }
            guard !shortMonthIsAWord(name, before: match.before(1)) else { return nil }
            return "\(SpokenVocabulary.monthNames[index - 1]) \(NumberWords.year(year))"
        }
        return result
    }

    /// "May" is a month and a verb; a match inside a longer word is neither.
    static func shortMonthIsAWord(_ name: String, before: String) -> Bool {
        if let last = before.last, last.isLetter { return true }
        return false
    }

    /// "Mon." → "Monday"; "Sat, 12 Jan" → "Saturday, …".
    static func weekdays(_ text: String) -> String {
        let names = SpokenVocabulary.alternation(SpokenVocabulary.weekdays.keys)
        var result = PatternRewriter.rewrite(text, #"(?<![\w])"# + names + #"\.(?=\s|,|$)"#) { match in
            guard let short = match[1], let full = SpokenVocabulary.weekdays[short] else { return nil }
            return full + (match.endsSentence ? "." : "")
        }
        result = PatternRewriter.rewrite(
            result, #"(?<![\w])"# + names + #"(?=,?\s+(?:the\s+)?\d{1,2}(?:st|nd|rd|th)?\b)"#
        ) { match in
            match[1].flatMap { SpokenVocabulary.weekdays[$0] }
        }
        return result
    }

    /// "9:45 pm", "9pm", "21:30", "9:05".
    static func times(_ text: String) -> String {
        let meridiem = #"([AaPp])\.?\s?[Mm]\.?(?![A-Za-z])"#
        var result = PatternRewriter.rewrite(text, #"(?<![\d:.])(\d{1,2})[:.]([0-5]\d)\s*"# + meridiem) { match in
            guard let hour = match[1].flatMap(Int.init), (0...12).contains(hour),
                  let minute = match[2].flatMap(Int.init), let half = match[3] else { return nil }
            return clock(hour, minute, sayOClock: false) + " " + suffix(half)
        }
        result = PatternRewriter.rewrite(result, #"(?<![\d:.,])(\d{1,2})\s?"# + meridiem) { match in
            guard let hour = match[1].flatMap(Int.init), (1...12).contains(hour), let half = match[2] else { return nil }
            return NumberWords.cardinal(hour) + " " + suffix(half)
        }
        result = PatternRewriter.rewrite(result, #"(?<![\d:.])([01]?\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?(?![\d:])"#) { match in
            guard let hour = match[1].flatMap(Int.init), let minute = match[2].flatMap(Int.init) else { return nil }
            var words = clock(hour, minute, sayOClock: true)
            if let second = match[3].flatMap(Int.init), second > 0 {
                words += " and " + NumberWords.counted(second, "second", "seconds")
            }
            return words
        }
        return result
    }

    static func suffix(_ half: String) -> String {
        half.lowercased() == "a" ? "a.m." : "p.m."
    }

    /// 9:05 → "nine oh five"; 9:00 → "nine o'clock"; 14:00 → "fourteen hundred".
    static func clock(_ hour: Int, _ minute: Int, sayOClock: Bool) -> String {
        let hourWords = NumberWords.cardinal(hour)
        switch minute {
        case 0:
            if !sayOClock { return hourWords }
            return hour > 12 || hour == 0 ? hourWords + " hundred" : hourWords + " o'clock"
        case 1..<10: return hourWords + " oh " + NumberWords.cardinal(minute)
        default: return hourWords + " " + NumberWords.cardinal(minute)
        }
    }

    /// "10-20", "1990–1995", "$10–$20", "9:00-17:00" → "… to …".
    ///
    /// An en or em dash always marks a range; a hyphen only when nothing
    /// separates it from the numbers, so "5 - 3" is left alone.
    static func ranges(_ text: String) -> String {
        let side = #"[$£€¥₹]?\d[\d,]*(?:[.:]\d+)?"#
        return PatternRewriter.rewrite(
            text, #"(?<![\w.,:/-])("# + side + #")(?:\s?[–—]\s?|-)("# + side + #")(?![\w/-]|[.:]\d)"#
        ) { match in
            guard let low = match[1], let high = match[2] else { return nil }
            return "\(low) to \(high)"
        }
    }

    /// "$1,250.50", "£82.99", "€3.50", "¥500", "$2.5bn", "100 USD", "50p".
    static func money(_ text: String) -> String {
        let scale = #"(?:\s?(thousand|million|billion|trillion|bn|mn|tn|[kKmMbB])(?![\w]))?"#
        var result = PatternRewriter.rewrite(
            text, #"(?<![\w$£€¥₹])(-)?"# + SpokenVocabulary.symbolPattern + #"\s?("# + number + ")" + scale
        ) { match in
            guard let symbol = match[2], let currency = SpokenVocabulary.symbols[symbol],
                  let amount = match[3] else { return nil }
            return (match[1] == nil ? "" : "minus ") + spokenAmount(amount, currency: currency, scale: match[4])
        }
        result = PatternRewriter.rewrite(
            result, #"(?<![\w])("# + number + #")\s?"# + SpokenVocabulary.codePattern + #"(?![\w])"#
        ) { match in
            guard let amount = match[1], let code = match[2], let currency = SpokenVocabulary.codes[code] else { return nil }
            return spokenAmount(amount, currency: currency, scale: nil)
        }
        result = PatternRewriter.rewrite(
            result, #"(?<![\w])"# + SpokenVocabulary.codePattern + #"\s?("# + number + ")" + scale
        ) { match in
            guard let code = match[1], let currency = SpokenVocabulary.codes[code], let amount = match[2] else { return nil }
            return spokenAmount(amount, currency: currency, scale: match[3])
        }
        // Pence and cents on their own: "50p", "99¢".
        result = PatternRewriter.rewrite(result, #"(?<![\w.,])(\d+)(p|¢)(?![\w])"#) { match in
            guard let value = match[1].flatMap(Int.init), let mark = match[2] else { return nil }
            return mark == "p" ? NumberWords.counted(value, "penny", "pence") : NumberWords.counted(value, "cent", "cents")
        }
        return result
    }

    /// An amount in a currency: "1,250.50" → "one thousand two hundred fifty
    /// dollars and fifty cents"; with a scale, "2.5" + "bn" → "two point
    /// five billion dollars".
    static func spokenAmount(_ amount: String, currency: SpokenVocabulary.Currency, scale: String?) -> String {
        if let scale, let scaleWord = SpokenVocabulary.scales[scale] {
            return NumberWords.decimal(amount) + " " + scaleWord + " " + currency.many
        }
        let plain = amount.replacingOccurrences(of: ",", with: "")
        let parts = plain.split(separator: ".", omittingEmptySubsequences: false)
        let whole = parts.first.flatMap { Int($0) } ?? 0
        guard parts.count == 2 else { return NumberWords.counted(whole, currency.one, currency.many) }
        let fraction = String(parts[1])
        // More than two decimals is a rate, not a price: "$0.125" → "zero point one two five dollars".
        guard fraction.count <= 2, let minorOne = currency.minorOne, let minorMany = currency.minorMany else {
            return NumberWords.decimal(plain) + " " + currency.many
        }
        let minor = Int(fraction.count == 1 ? fraction + "0" : fraction) ?? 0
        let major = NumberWords.counted(whole, currency.one, currency.many)
        if minor == 0 { return major }
        let minorWords = NumberWords.counted(minor, minorOne, minorMany)
        return whole == 0 ? minorWords : major + " and " + minorWords
    }

    /// "15%" → "fifteen percent", "2.5 %" → "two point five percent".
    static func percentages(_ text: String) -> String {
        PatternRewriter.rewrite(text, #"(?<![\w.,])(-)?("# + number + #")\s?%"#) { match in
            guard let value = match[2] else { return nil }
            return (match[1] == nil ? "" : "minus ") + spokenNumber(value) + " percent"
        }
    }

    /// "1990s" → "nineteen nineties", "'80s" → "eighties".
    static func decades(_ text: String) -> String {
        PatternRewriter.rewrite(text, #"(?<![\w'’])['’]?(\d{2}|\d{4})['’]?s(?![\w])"#) { match in
            guard let digits = match[1], let value = Int(digits), value % 10 == 0 else { return nil }
            let words = digits.count == 4 ? NumberWords.year(value) : NumberWords.cardinal(value)
            guard value != 0 else { return nil }
            let cut = words.lastIndex(of: " ").map { words.index(after: $0) } ?? words.startIndex
            return String(words[..<cut]) + NumberWords.plural(String(words[cut...]))
        }
    }

    /// "5 km" → "five kilometers", "1 kg" → "one kilogram", "20°C".
    static func units(_ text: String) -> String {
        PatternRewriter.rewrite(
            text, #"(?<![\w.,])(-)?("# + number + #")\s?"# + SpokenVocabulary.unitPattern + #"(?![\w²])"#
        ) { match in
            guard let value = match[2], let symbol = match[3], let unit = SpokenVocabulary.units[symbol] else { return nil }
            // "x" is a multiplier only straight after the number: "2x", not "2 x 4".
            if symbol == "x", match[0]?.contains(" ") == true { return nil }
            let words = (match[1] == nil ? "" : "minus ") + spokenNumber(value)
            if symbol == "x" { return words + " times" }
            return words + " " + (value == "1" ? unit.one : unit.many)
        }
    }

    /// "21st" → "twenty-first".
    static func ordinals(_ text: String) -> String {
        PatternRewriter.rewrite(text, #"(?<![\w.,])(\d{1,3}(?:,\d{3})+|\d+)(st|nd|rd|th|ST|ND|RD|TH)(?![\w])"#) { match in
            guard let value = match[1].map({ $0.replacingOccurrences(of: ",", with: "") }).flatMap(Int.init) else {
                return nil
            }
            return NumberWords.ordinal(value)
        }
    }

    /// Titles before names, abbreviations with full stops, and the ones that
    /// only mean something before a number.
    static func abbreviations(_ text: String) -> String {
        // Before a number: "No. 4471", "fig. 3", "#5".
        var result = PatternRewriter.rewrite(
            text, #"(?<![\w.])"# + SpokenVocabulary.alternation(SpokenVocabulary.beforeNumber.keys) + #"\s?(?=\d)"#
        ) { match in
            match[1].flatMap { SpokenVocabulary.beforeNumber[$0] }.map { $0 + " " }
        }
        // Titles before a capitalised word.
        let titles = SpokenVocabulary.alternation(SpokenVocabulary.titles.keys)
        result = PatternRewriter.rewrite(result, #"(?<![\w.])"# + titles + #"(\.)?(?=\s+[A-Z])"#) { match in
            guard let title = match[1], let words = SpokenVocabulary.titles[title] else { return nil }
            if match[2] == nil && !SpokenVocabulary.undottedTitles.contains(title) { return nil }
            // "Main St. Paul…" is an address; a word or number in capitals before
            // St./Dr. makes it the street or drive, not the saint or doctor.
            if title == "St" || (title == "Dr" && match[2] != nil) {
                let previous = match.before(16).split(separator: " ").last.map(String.init) ?? ""
                let addressy = previous.first.map { $0.isUppercase || $0.isNumber } ?? false
                if addressy && !previous.hasSuffix(".") && !previous.hasSuffix(",") { return nil }
            }
            return words
        }
        // Dotted abbreviations anywhere.
        result = PatternRewriter.rewrite(
            result, #"(?<![\w.])"# + SpokenVocabulary.alternation(SpokenVocabulary.dotted.keys) + #"(?![\w])"#
        ) { match in
            guard let short = match[1], let words = SpokenVocabulary.dotted[short] else { return nil }
            return words + (match.endsSentence ? "." : "")
        }
        // "vs" without its full stop, "w/" and "&".
        result = PatternRewriter.rewrite(result, #"(?<![\w])(vs|w/o|w/)(?![\w])"#) { match in
            switch match[1] {
            case "vs": return "versus"
            case "w/o": return "without"
            case "w/": return "with"
            default: return nil
            }
        }
        return result
    }

    /// "1/2" → "one half", "3/4" → "three quarters", "24/7", "50/50".
    static func fractions(_ text: String) -> String {
        PatternRewriter.rewrite(text, #"(?<![\w/.,])(\d{1,3})/(\d{1,3})(?![\w/]|[.,]\d)"#) { match in
            guard let top = match[1].flatMap(Int.init), let bottom = match[2].flatMap(Int.init), bottom > 0 else {
                return nil
            }
            if top == 24 && bottom == 7 { return "twenty-four seven" }
            if top == bottom && top == 50 { return "fifty-fifty" }
            return NumberWords.fraction(top, bottom)
        }
    }

    /// Every number left: "-5", "1,000,000", "3.14", ".5", "007", "2025".
    static func numbers(_ text: String) -> String {
        // A minus sign in front of a number, not a hyphen between words.
        var result = PatternRewriter.rewrite(text, #"(?<![\w.,])-(?=\d)"#) { _ in "minus " }
        result = PatternRewriter.rewrite(result, #"(?<![\d.,])("# + number + #"|\.\d+)(?!\d)"#) { match in
            guard let value = match[1] else { return nil }
            let before = match.before(1).last, after = match.after(1).first
            var words = value.contains(".") || value.contains(",")
                ? NumberWords.decimal(value)
                : wholeNumber(value, previousWords: match.before(12))
            // "MP3", "3D", "4K": keep the number its own word.
            if let before, before.isLetter { words = " " + words }
            if let after, after.isLetter { words += " " }
            return words
        }
        // Anything the rules above could not place — the "1" of "2.0.1" —
        // still goes out as words, never as a digit.
        result = PatternRewriter.rewrite(result, #"\.?\d+"#) { match in
            guard let value = match[0] else { return nil }
            return value.hasPrefix(".") ? " point " + NumberWords.digits(value) : NumberWords.integer(value)
        }
        return result
    }

    /// A bare integer: a year when it looks like one, digit by digit when
    /// it starts with zero, otherwise a cardinal.
    static func wholeNumber(_ digits: String, previousWords: String) -> String {
        guard let value = Int(digits), digits.count <= 15 else { return NumberWords.digits(digits) }
        if digits.count > 1 && digits.hasPrefix("0") { return NumberWords.digits(digits) }
        // Four digits from 1000 to 2099 read as a year — "in 1066", "the
        // 2025 estimate" — except as a count: "number 1984".
        let counted = previousWords.lowercased().hasSuffix("number ")
        if digits.count == 4 && (1000...2099).contains(value) && !counted { return NumberWords.year(value) }
        return NumberWords.cardinal(value)
    }

    /// "3.14" → "three point one four"; "12" → "twelve".
    static func spokenNumber(_ value: String) -> String {
        value.contains(".") || value.contains(",") ? NumberWords.decimal(value) : NumberWords.integer(value)
    }

    /// Symbols a reader says as words.
    static func symbols(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "&", with: " and ")
        result = result.replacingOccurrences(of: "%", with: " percent")
        result = PatternRewriter.rewrite(result, #"(?<=\s)([+=×÷≈~])(?=\s)"#) { match in
            switch match[1] {
            case "+": return "plus"
            case "=": return "equals"
            case "×": return "times"
            case "÷": return "divided by"
            case "≈", "~": return "about"
            default: return nil
            }
        }
        result = PatternRewriter.rewrite(result, #"(?<=\s|^)[~≈](?=\s?\w)"#) { _ in "about " }
        result = PatternRewriter.rewrite(result, #"(?<=\w)@(?=\w)"#) { _ in " at " }
        return result
    }

    /// Single spaces, none before punctuation; line breaks kept.
    static func tidy(_ text: String) -> String {
        var result = PatternRewriter.rewrite(text, #"[ \t]{2,}"#) { _ in " " }
        result = PatternRewriter.rewrite(result, #"[ \t]+(?=[,.;:!?])"#) { _ in "" }
        return result.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }
}
