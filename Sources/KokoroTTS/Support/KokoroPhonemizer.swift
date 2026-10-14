//
//  KokoroPhonemizer.swift
//  KokoroTTS
//
//  Created by David Sherlock on 2026.
//
//  Kokoro's front end: Misaki's lexicon first, the neural G2P for the words
//  it does not have, both read from the files FluidAudio downloads.
//

import Foundation
import SpeechSynthesizer

/// Text → Kokoro phonemes, in a US or British accent.
actor KokoroPhonemizer {

    private let directory: URL
    private var readers: [Bool: MisakiG2P] = [:]
    private let neural: NeuralG2P
    private var guesses: [String: String] = [:]
    private var vocabulary: Set<Character>?

    init(directory: URL = KokoroFiles.textDirectory) {
        self.directory = directory
        self.neural = NeuralG2P(directory: directory)
    }

    /// Loads an accent's lexicons now rather than on first use.
    func prepare(british: Bool) throws {
        _ = try reader(british: british)
    }

    /// `text` (already normalised) as phonemes Kokoro can encode.
    func phonemes(_ text: String, british: Bool) async throws -> String {
        let reader = try reader(british: british)
        var reading = reader.read(text, guesses: guesses)
        if !reading.unknown.isEmpty {
            for word in reading.unknown {
                let key = MisakiG2P.guessKey(word)
                guard guesses[key] == nil else { continue }
                guesses[key] = try await neural.phonemes(for: key) ?? ""
            }
            reading = reader.read(text, guesses: guesses)
        }
        return encodable(reading.phonemes)
    }

    private func reader(british: Bool) throws -> MisakiG2P {
        if let reader = readers[british] { return reader }
        let reader = MisakiG2P(lexicon: try MisakiLexicon.load(from: directory, british: british))
        readers[british] = reader
        return reader
    }

    /// Drops any symbol outside the model's vocabulary, which the encoder
    /// would drop anyway. Every symbol in the lexicons and the neural G2P's
    /// output is inside it (checked on the 2026-10-15 files); this is a guard.
    private func encodable(_ phonemes: String) -> String {
        if vocabulary == nil {
            vocabulary = (try? KokoroPhonemes.vocabulary(in: KokoroFiles.modelDirectory)) ?? []
        }
        guard let vocabulary, !vocabulary.isEmpty else { return phonemes }
        return String(phonemes.filter { $0 == " " || vocabulary.contains($0) })
    }
}
