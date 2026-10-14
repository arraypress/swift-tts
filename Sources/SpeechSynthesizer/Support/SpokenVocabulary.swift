//
//  SpokenVocabulary.swift
//  SpeechSynthesizer
//
//  Created by David Sherlock on 2026.
//
//  The word lists behind SpokenText: months, weekdays, currencies, units
//  and abbreviations, each with the words a reader says for it.
//

import Foundation

enum SpokenVocabulary {

    // MARK: - Calendar

    static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    /// Every spelling of a month the rules accept, longest first so the
    /// alternation prefers "Sept" over "Sep" and "June" over "Jun".
    static let monthPattern: String = {
        let short = ["Jan", "Feb", "Mar", "Apr", "Jun", "Jul", "Aug", "Sept", "Sep", "Oct", "Nov", "Dec"]
        let all = (monthNames + short + monthNames.map { $0.uppercased() } + short.map { $0.uppercased() })
        return "(" + Set(all).sorted { $0.count > $1.count || ($0.count == $1.count && $0 < $1) }
            .joined(separator: "|") + ")"
    }()

    /// "Oct", "oct", "OCT" or "October" → 10.
    static func month(_ text: String) -> Int? {
        let key = text.lowercased().prefix(3)
        return monthNames.firstIndex { $0.lowercased().hasPrefix(key) }.map { $0 + 1 }
    }

    static let weekdays: [String: String] = [
        "Mon": "Monday", "Tue": "Tuesday", "Tues": "Tuesday", "Wed": "Wednesday",
        "Thu": "Thursday", "Thur": "Thursday", "Thurs": "Thursday", "Fri": "Friday",
        "Sat": "Saturday", "Sun": "Sunday",
    ]

    // MARK: - Money

    /// What a currency's units are called, one and many, and its minor unit.
    struct Currency {
        let one: String
        let many: String
        let minorOne: String?
        let minorMany: String?
    }

    static let dollar = Currency(one: "dollar", many: "dollars", minorOne: "cent", minorMany: "cents")

    /// Prefix symbols, longest first in ``symbolPattern``.
    static let symbols: [String: Currency] = [
        "$": dollar,
        "US$": dollar,
        "A$": Currency(one: "Australian dollar", many: "Australian dollars", minorOne: "cent", minorMany: "cents"),
        "AU$": Currency(one: "Australian dollar", many: "Australian dollars", minorOne: "cent", minorMany: "cents"),
        "C$": Currency(one: "Canadian dollar", many: "Canadian dollars", minorOne: "cent", minorMany: "cents"),
        "CA$": Currency(one: "Canadian dollar", many: "Canadian dollars", minorOne: "cent", minorMany: "cents"),
        "NZ$": Currency(one: "New Zealand dollar", many: "New Zealand dollars", minorOne: "cent", minorMany: "cents"),
        "HK$": Currency(one: "Hong Kong dollar", many: "Hong Kong dollars", minorOne: "cent", minorMany: "cents"),
        "S$": Currency(one: "Singapore dollar", many: "Singapore dollars", minorOne: "cent", minorMany: "cents"),
        "R$": Currency(one: "real", many: "reais", minorOne: "centavo", minorMany: "centavos"),
        "£": Currency(one: "pound", many: "pounds", minorOne: "penny", minorMany: "pence"),
        "€": Currency(one: "euro", many: "euros", minorOne: "cent", minorMany: "cents"),
        "¥": Currency(one: "yen", many: "yen", minorOne: nil, minorMany: nil),
        "₹": Currency(one: "rupee", many: "rupees", minorOne: "paisa", minorMany: "paise"),
        "₩": Currency(one: "won", many: "won", minorOne: nil, minorMany: nil),
        "₽": Currency(one: "rouble", many: "roubles", minorOne: "kopek", minorMany: "kopeks"),
        "₺": Currency(one: "lira", many: "lira", minorOne: "kuruş", minorMany: "kuruş"),
        "₪": Currency(one: "shekel", many: "shekels", minorOne: "agora", minorMany: "agorot"),
        "₦": Currency(one: "naira", many: "naira", minorOne: "kobo", minorMany: "kobo"),
        "₱": Currency(one: "peso", many: "pesos", minorOne: "centavo", minorMany: "centavos"),
    ]

    /// ISO codes, written before or after the amount: "100 USD", "EUR 50".
    static let codes: [String: Currency] = [
        "USD": dollar,
        "EUR": symbols["€"]!,
        "GBP": symbols["£"]!,
        "JPY": symbols["¥"]!,
        "INR": symbols["₹"]!,
        "CAD": symbols["C$"]!,
        "AUD": symbols["A$"]!,
        "NZD": symbols["NZ$"]!,
        "CHF": Currency(one: "Swiss franc", many: "Swiss francs", minorOne: "centime", minorMany: "centimes"),
        "CNY": Currency(one: "yuan", many: "yuan", minorOne: nil, minorMany: nil),
    ]

    static var symbolPattern: String { alternation(symbols.keys) }
    static var codePattern: String { alternation(codes.keys) }

    /// "k", "m", "bn"… after an amount, and what they multiply by in words.
    static let scales: [String: String] = [
        "k": "thousand", "K": "thousand", "thousand": "thousand",
        "m": "million", "M": "million", "mn": "million", "million": "million",
        "b": "billion", "B": "billion", "bn": "billion", "billion": "billion",
        "tn": "trillion", "trillion": "trillion",
    ]

    // MARK: - Units

    /// Unit symbols after a number, and their words (one, many).
    ///
    /// Deliberately missing: `in` (the preposition), `s` and `t` (too many
    /// other readings), and a bare lower-case `l` (reads as a one).
    static let units: [String: (one: String, many: String)] = [
        "mm": ("millimeter", "millimeters"), "cm": ("centimeter", "centimeters"),
        "m": ("meter", "meters"), "km": ("kilometer", "kilometers"),
        "ft": ("foot", "feet"), "yd": ("yard", "yards"), "mi": ("mile", "miles"),
        "mph": ("mile per hour", "miles per hour"), "km/h": ("kilometer per hour", "kilometers per hour"),
        "kph": ("kilometer per hour", "kilometers per hour"), "m/s": ("meter per second", "meters per second"),
        "mg": ("milligram", "milligrams"), "g": ("gram", "grams"), "kg": ("kilogram", "kilograms"),
        "lb": ("pound", "pounds"), "lbs": ("pound", "pounds"), "oz": ("ounce", "ounces"),
        "ml": ("milliliter", "milliliters"), "mL": ("milliliter", "milliliters"), "cl": ("centiliter", "centiliters"),
        "L": ("liter", "liters"),
        "kWh": ("kilowatt hour", "kilowatt hours"), "kW": ("kilowatt", "kilowatts"), "W": ("watt", "watts"),
        "MW": ("megawatt", "megawatts"), "V": ("volt", "volts"), "mAh": ("milliamp hour", "milliamp hours"),
        "Hz": ("hertz", "hertz"), "kHz": ("kilohertz", "kilohertz"), "MHz": ("megahertz", "megahertz"),
        "GHz": ("gigahertz", "gigahertz"),
        "KB": ("kilobyte", "kilobytes"), "MB": ("megabyte", "megabytes"), "GB": ("gigabyte", "gigabytes"),
        "TB": ("terabyte", "terabytes"), "Mbps": ("megabit per second", "megabits per second"),
        "Gbps": ("gigabit per second", "gigabits per second"),
        "ms": ("millisecond", "milliseconds"), "sec": ("second", "seconds"), "secs": ("second", "seconds"),
        "min": ("minute", "minutes"), "mins": ("minute", "minutes"),
        "h": ("hour", "hours"), "hr": ("hour", "hours"), "hrs": ("hour", "hours"),
        "yr": ("year", "years"), "yrs": ("year", "years"),
        "°C": ("degree Celsius", "degrees Celsius"), "ºC": ("degree Celsius", "degrees Celsius"),
        "°F": ("degree Fahrenheit", "degrees Fahrenheit"), "ºF": ("degree Fahrenheit", "degrees Fahrenheit"),
        "°": ("degree", "degrees"), "º": ("degree", "degrees"),
        "km²": ("square kilometer", "square kilometers"), "m²": ("square meter", "square meters"),
        "sq ft": ("square foot", "square feet"), "kcal": ("kilocalorie", "kilocalories"),
        "x": ("times", "times"),
    ]

    static var unitPattern: String { alternation(units.keys) }

    // MARK: - Abbreviations

    /// Titles, read only before a capitalised name: "Dr. Smith", "Mr Jones".
    static let titles: [String: String] = [
        "Mr": "Mister", "Mrs": "Missus", "Ms": "Miz", "Mx": "Mix", "Dr": "Doctor", "Prof": "Professor",
        "Rev": "Reverend", "Hon": "Honourable", "Gen": "General", "Capt": "Captain", "Lt": "Lieutenant",
        "Col": "Colonel", "Sgt": "Sergeant", "Gov": "Governor", "Sen": "Senator", "Rep": "Representative",
        "Pres": "President", "Fr": "Father", "St": "Saint", "Mt": "Mount", "Ft": "Fort",
    ]

    /// Titles that British style writes without a full stop.
    static let undottedTitles: Set<String> = ["Mr", "Mrs", "Ms", "Mx", "Dr", "St"]

    /// Abbreviations read the same wherever they stand, with their full stop.
    static let dotted: [String: String] = [
        "Jr.": "Junior", "Sr.": "Senior", "St.": "Street", "Dr.": "Drive", "Ave.": "Avenue", "Rd.": "Road",
        "Blvd.": "Boulevard", "Ln.": "Lane", "Hwy.": "Highway", "Sq.": "Square", "Apt.": "Apartment",
        "Bldg.": "Building", "Inc.": "Incorporated", "Ltd.": "Limited", "Co.": "Company", "Corp.": "Corporation",
        "Bros.": "Brothers", "Dept.": "Department", "Univ.": "University", "approx.": "approximately",
        "Approx.": "Approximately", "etc.": "et cetera", "vs.": "versus", "avg.": "average",
        "e.g.": "for example", "E.g.": "For example", "i.e.": "that is", "I.e.": "That is",
        "a.k.a.": "also known as", "est.": "established", "Est.": "Established",
    ]

    /// Abbreviations read only before a number: "fig. 3", "p. 12", "No. 5".
    static let beforeNumber: [String: String] = [
        "No.": "number", "no.": "number", "Nos.": "numbers", "nos.": "numbers", "#": "number",
        "Fig.": "figure", "fig.": "figure", "Vol.": "volume", "vol.": "volume", "Ch.": "chapter",
        "ch.": "chapter", "p.": "page", "pp.": "pages", "Pg.": "page", "pg.": "page", "Sec.": "section",
        "sec.": "section", "Ext.": "extension", "ext.": "extension", "Tel.": "telephone", "tel.": "telephone",
        "Rm.": "room", "Ste.": "suite",
    ]

    /// `keys` as a regex alternation, escaped, longest first.
    static func alternation(_ keys: some Collection<String>) -> String {
        "(" + keys.sorted { $0.count > $1.count || ($0.count == $1.count && $0 < $1) }
            .map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")"
    }
}
