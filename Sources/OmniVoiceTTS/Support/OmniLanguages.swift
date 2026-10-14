//
//  OmniLanguages.swift
//  OmniVoiceTTS
//
//  Created by David Sherlock on 2026.
//
//  OmniVoice is told the language as a code from its own table (646 of them,
//  mostly ISO 639-3) or not at all, in which case it works the language out
//  from the text. The reference turns names into codes and silently drops
//  anything it does not know; here an unknown language is an error, and the
//  BCP-47 tags the rest of the fleet passes ("en-US", "pt_BR") resolve by
//  their primary subtag.
//

import Foundation

/// The languages OmniVoice was trained on, and how a caller names one.
public enum OmniLanguages {

    /// Lower-cased language name → code, from the reference's table.
    static let nameToCode: [String: String] = {
        var map: [String: String] = [:]
        for line in table.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            if parts.count == 2 { map[String(parts[0])] = String(parts[1]) }
        }
        return map
    }()

    /// Every code the model knows.
    public static let codes: Set<String> = Set(nameToCode.values)

    /// How many languages the table names.
    public static var count: Int { codes.count }

    /// The model's code for `language`: one of its codes (`en`, `yue`, `arb`),
    /// a name (`English`, `Cantonese`), or a BCP-47 tag (`en-US`, `pt_BR`,
    /// `ar-EG`) whose primary subtag or its English name is in the table.
    ///
    /// - Throws: ``OmniVoiceError/unsupportedLanguage(_:)``.
    public static func resolve(_ language: String) throws(OmniVoiceError) -> String {
        let trimmed = language.trimmingCharacters(in: .whitespaces)
        if codes.contains(trimmed) { return trimmed }
        let lowered = trimmed.lowercased()
        if codes.contains(lowered) { return lowered }
        if let code = nameToCode[lowered] { return code }
        let primary = String(lowered.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "")
        if codes.contains(primary) { return primary }
        if let name = Locale(identifier: "en").localizedString(forLanguageCode: primary)?.lowercased() {
            if let code = nameToCode[name] ?? nameToCode["standard " + name] { return code }
        }
        throw .unsupportedLanguage(language)
    }
}
