//
//  PocketVoices.swift
//  PocketTTS
//
//  Created by David Sherlock on 2026.
//
//  PocketTTS's English preset voices, each with the licence of the recording
//  it was made from.
//
//  The model's weights are CC BY 4.0, but a preset voice is a recording of
//  someone and keeps its source's terms. Kyutai's voice repository
//  (huggingface.co/kyutai/tts-voices, README, read 2026-10-14) gives them per
//  dataset, and the pocket-tts model card maps each voice to its file:
//
//  - vctk/ — VCTK, CC BY 4.0
//  - alba-mackenna/ — CC BY 4.0
//  - voice-donations/, voice-zero/ — CC0
//  - expresso/ — Expresso, CC BY-NC 4.0, "Non-commercial use only" → cosette
//  - ears/ — EARS, CC BY-NC 4.0, "Non-commercial use only" → jean
//
//  The converted pack ships 26 voices; the five recorded in other languages
//  (estelle, giovanni, juergen, lola, rafael) belong to Kyutai's other
//  language models and are not offered by this English engine.
//

import Foundation
import SpeechSynthesizer

/// PocketTTS's English preset voices and their licences.
public enum PocketVoices {

    /// The voice used when none is chosen. Commercial-safe, and checked to be:
    /// a non-commercial voice must never be anybody's default.
    public static let defaultID = "alba"

    /// Every English preset, as `(id, licence)` — the recording's licence,
    /// stated for every voice rather than left to the model's.
    static let english: [(id: String, license: String)] = [
        ("alba", "CC-BY-4.0"),
        ("anna", "CC-BY-4.0"),
        ("azelma", "CC-BY-4.0"),
        ("bill_boerst", "CC0-1.0"),
        ("caro_davy", "CC0-1.0"),
        ("charles", "CC-BY-4.0"),
        ("cosette", "CC-BY-NC-4.0"),
        ("eponine", "CC-BY-4.0"),
        ("eve", "CC-BY-4.0"),
        ("fantine", "CC-BY-4.0"),
        ("george", "CC-BY-4.0"),
        ("jane", "CC-BY-4.0"),
        ("javert", "CC0-1.0"),
        ("jean", "CC-BY-NC-4.0"),
        ("marius", "CC0-1.0"),
        ("mary", "CC-BY-4.0"),
        ("michael", "CC-BY-4.0"),
        ("paul", "CC-BY-4.0"),
        ("peter_yearsley", "CC0-1.0"),
        ("stuart_bell", "CC0-1.0"),
        ("vera", "CC-BY-4.0"),
    ]

    /// Whether a licence string is a non-commercial one.
    static func isNonCommercial(_ license: String) -> Bool {
        license.contains("NC")
    }

    /// The voices that may not be used commercially.
    public static var nonCommercialIDs: [String] {
        english.filter { isNonCommercial($0.license) }.map(\.id)
    }

    /// The presets as voice descriptors.
    public static func voices() -> [TTSVoice] {
        english.map { entry in
            let words = entry.id.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }
            var name = words.joined(separator: " ")
            if isNonCommercial(entry.license) { name += " (non-commercial)" }
            return TTSVoice(
                id: entry.id, name: name, language: "en", model: .pocket,
                license: entry.license, isCommercialUseAllowed: !isNonCommercial(entry.license)
            )
        }
    }
}
