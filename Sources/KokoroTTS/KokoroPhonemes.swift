//
//  KokoroPhonemes.swift
//  KokoroTTS
//
//  Created by David Sherlock on 2026.
//

import Foundation
import SpeechSynthesizer

// FluidAudio also exports a `TTSError`; ours is the one we throw.
private typealias TTSError = SpeechSynthesizer.TTSError

/// Speaking IPA directly, and checking it first.
///
/// Kokoro is text → grapheme-to-phoneme → three non-autoregressive CoreML
/// stages. Only the first step is suspect: FluidAudio ships a small *neural*
/// G2P rather than Kokoro's reference Misaki, and it mispronounces real words
/// — measured, `turmoil` comes back as "terminal". The stages after it are
/// fine, which PocketTTS through the same pipeline demonstrates.
///
/// So the phoneme path is not a power-user flourish. It is the way to use the
/// good three-quarters of this model when the G2P has let you down, and the
/// only way to be certain of a pronunciation.
///
/// The phonemes are espeak-flavoured IPA, the same convention Kokoro was
/// trained on.
public enum KokoroPhonemes {

    /// The symbols the model can encode, read from the vocabulary it ships.
    ///
    /// Loaded from disk rather than hard-coded: the vocabulary travels with
    /// the converted model, and a list copied into this file would be a second
    /// source of truth that silently rots when the model is updated.
    public static func vocabulary(
        in directory: URL = KokoroVoicePacks.cacheDirectory
    ) throws -> Set<Character> {
        let url = directory.appendingPathComponent("vocab.json")
        guard let data = try? Data(contentsOf: url) else {
            throw TTSError.synthesisFailed(
                "no vocab.json in \(directory.path) — synthesise once to fetch the model first"
            )
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TTSError.synthesisFailed("vocab.json is not a JSON object")
        }
        return Set(json.keys.compactMap { $0.count == 1 ? $0.first : nil })
    }

    /// The characters in `phonemes` this model cannot say, in the order met.
    ///
    /// Worth checking, because the encoder does not. Its reference
    /// implementation drops anything it does not recognise — silently, and
    /// mid-word — so a single stray symbol turns into a plausible-sounding
    /// mispronunciation rather than an error. That is the failure mode this
    /// whole feature exists to escape, so reproducing it here would be
    /// perverse.
    public static func unsupported(
        _ phonemes: String, vocabulary: Set<Character>
    ) -> [Character] {
        var seen: Set<Character> = []
        return phonemes.filter { character in
            // Whitespace separates words and never reaches the encoder.
            guard !character.isWhitespace, !vocabulary.contains(character) else { return false }
            return seen.insert(character).inserted
        }
    }

    /// Checks a phoneme string, throwing if the model would drop part of it.
    public static func validate(
        _ phonemes: String, in directory: URL = KokoroVoicePacks.cacheDirectory
    ) throws {
        let trimmed = phonemes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TTSError.emptyText }

        let missing = unsupported(trimmed, vocabulary: try vocabulary(in: directory))
        guard missing.isEmpty else {
            let list = missing.map(String.init).joined(separator: " ")
            throw TTSError.synthesisFailed(
                "these are not in Kokoro's phoneme vocabulary and would be dropped without a sound: \(list)"
            )
        }
    }
}
