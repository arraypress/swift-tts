//
//  KokoroVoices.swift
//  KokoroTTS
//
//  Created by David Sherlock on 2026.
//

import Foundation
import SpeechSynthesizer

/// Every voice Kokoro-82M was trained with.
///
/// The CoreML conversion this engine runs on ships exactly one English voice
/// pack — `af_heart` — so for a long time this list was five entries long and
/// four of them answered a 404 at synthesis time, after the caller had already
/// chosen one. The packs for the rest exist; they are just in the original
/// model repository rather than the converted one, in a format that turns out
/// to be the same bytes wrapped differently. See ``KokoroVoicePacks``.
public enum KokoroVoices {

    /// The letter pairs Kokoro encodes into every voice id.
    ///
    /// First letter is the language, second is the speaker's gender: `bf_emma`
    /// is British female. Worth spelling out because the ids are otherwise
    /// opaque and there are fifty-four of them.
    static func describe(_ id: String) -> (language: String, name: String) {
        let parts = id.split(separator: "_", maxSplits: 1)
        guard parts.count == 2 else { return ("en-US", id) }

        let prefix = String(parts[0])
        let given = parts[1].prefix(1).uppercased() + parts[1].dropFirst()

        let (code, place): (String, String) = switch prefix.prefix(1) {
        case "a": ("en-US", "US")
        case "b": ("en-GB", "UK")
        case "j": ("ja-JP", "Japanese")
        case "z": ("zh-CN", "Mandarin")
        case "e": ("es-ES", "Spanish")
        case "f": ("fr-FR", "French")
        case "h": ("hi-IN", "Hindi")
        case "i": ("it-IT", "Italian")
        case "p": ("pt-BR", "Brazilian")
        default: ("en-US", "US")
        }
        let gender = prefix.hasSuffix("m") ? "male" : "female"
        return (code, "\(given) (\(place), \(gender))")
    }

    /// The ids, as the model names them.
    ///
    /// Taken from `hexgrad/Kokoro-82M`, which is where the packs come from.
    /// American and British English are the ones with a full cast; the other
    /// languages ship a handful each.
    public static let ids: [String] = [
        // American English
        "af_alloy", "af_aoede", "af_bella", "af_heart", "af_jessica", "af_kore",
        "af_nicole", "af_nova", "af_river", "af_sarah", "af_sky",
        "am_adam", "am_echo", "am_eric", "am_fenrir", "am_liam", "am_michael",
        "am_onyx", "am_puck", "am_santa",
        // British English
        "bf_alice", "bf_emma", "bf_isabella", "bf_lily",
        "bm_daniel", "bm_fable", "bm_george", "bm_lewis",
        // Everything else
        "ef_dora", "em_alex", "em_santa",
        "ff_siwis",
        "hf_alpha", "hf_beta", "hm_omega", "hm_psi",
        "if_sara", "im_nicola",
        "jf_alpha", "jf_gongitsune", "jf_nezumi", "jf_tebukuro", "jm_kumo",
        "pf_dora", "pm_alex", "pm_santa",
        "zf_xiaobei", "zf_xiaoni", "zf_xiaoxiao", "zf_xiaoyi",
        "zm_yunjian", "zm_yunxi", "zm_yunxia", "zm_yunyang",
    ]

    /// The English voices, which are the ones this engine can actually speak.
    ///
    /// The CoreML English pipeline is built around an English phoneme
    /// vocabulary. A Japanese or Mandarin pack would load and produce sound,
    /// but not the sound anybody wanted, so they are kept out of the list
    /// rather than offered and disappointing.
    public static var english: [String] {
        ids.filter { $0.hasPrefix("a") || $0.hasPrefix("b") }
    }

    /// The list an engine reports.
    public static func voices() -> [TTSVoice] {
        english.map { id in
            let described = describe(id)
            return TTSVoice(
                id: id, name: described.name, language: described.language, model: .kokoro
            )
        }
    }

    /// Whether this is a voice the engine will accept.
    public static func exists(_ id: String) -> Bool {
        english.contains(id)
    }
}
