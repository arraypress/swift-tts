//
//  MisakiLexicon.swift
//  KokoroTTS
//
//  Created by David Sherlock on 2026.
//
//  Kokoro's reference pronouncing dictionary.
//
//  Misaki (hexgrad/misaki, Apache-2.0) is the front end Kokoro was trained
//  behind. Its two English lexicons per accent — `gold` (checked by hand)
//  and `silver` (larger, less certain) — map a word to phonemes in the
//  model's own symbol set, or to one spelling per part of speech where the
//  word has several ("read", "live", "wind"). FluidAudio already downloads
//  them beside its G2P model (`us_gold.json`, `us_silver.json`,
//  `gb_gold.json`, `gb_silver.json`), and then never reads them.
//

import Foundation
import SpeechSynthesizer

// FluidAudio also exports a `TTSError`; ours is the one we throw.
private typealias TTSError = SpeechSynthesizer.TTSError

/// One accent's pronouncing dictionary.
struct MisakiLexicon: Sendable {

    /// A word's phonemes: one spelling, or one per part-of-speech tag
    /// ("DEFAULT", "VERB", "NOUN", "None" for the end of a phrase…). A
    /// tagged spelling may be `nil`: Misaki's "no reading here; spell it".
    enum Entry: Sendable, Equatable {
        case plain(String)
        case tagged([String: String?])
    }

    let gold: [String: Entry]
    let silver: [String: Entry]
    let british: Bool

    init(gold: [String: Entry], silver: [String: Entry], british: Bool) {
        self.gold = gold
        self.silver = silver
        self.british = british
    }

    /// The four files, by accent.
    static func files(british: Bool) -> [String] {
        british ? ["gb_gold.json", "gb_silver.json"] : ["us_gold.json", "us_silver.json"]
    }

    /// Reads one accent's lexicons from `directory`.
    static func load(from directory: URL, british: Bool) throws -> MisakiLexicon {
        let names = files(british: british)
        return MisakiLexicon(
            gold: try entries(directory.appendingPathComponent(names[0])),
            silver: try entries(directory.appendingPathComponent(names[1])),
            british: british
        )
    }

    static func entries(_ url: URL) throws -> [String: Entry] {
        guard let data = try? Data(contentsOf: url) else {
            throw TTSError.modelDownloadFailed("Kokoro's pronouncing dictionary is missing: \(url.path)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TTSError.synthesisFailed("\(url.lastPathComponent) is not a JSON object")
        }
        var result: [String: Entry] = [:]
        result.reserveCapacity(json.count)
        for (word, value) in json {
            if let phonemes = value as? String {
                result[word] = .plain(phonemes)
            } else if let tagged = value as? [String: Any] {
                result[word] = .tagged(tagged.mapValues { $0 as? String })
            }
        }
        return result
    }
}
