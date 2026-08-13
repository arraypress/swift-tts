//
//  KokoroPhonemeTests.swift
//  KokoroTTS
//
//  Created by David Sherlock on 2026.
//

import Foundation
import Testing
@testable import KokoroTTS

// The real vocabulary is 114 single-character symbols read from the model's
// vocab.json. These use a small stand-in so the tests need no model on disk.
private let vocabulary: Set<Character> = Set("təɜːmɔɪlðwdɪzˈ .")

// MARK: - Catching what the encoder would swallow

@Test func supportedPhonemesAreLeftAlone() {
    let phrase = "ðə wˈɜːd ɪz tˈɜːmɔɪl."
    #expect(KokoroPhonemes.unsupported(phrase, vocabulary: vocabulary).isEmpty)
}

@Test func unsupportedSymbolsAreReported() {
    // The encoder's reference behaviour is to drop these silently, mid-word,
    // and produce a confident mispronunciation instead of an error.
    let found = KokoroPhonemes.unsupported("tˈɜːmɔɪl###", vocabulary: vocabulary)
    #expect(found == ["#"])
}

@Test func eachUnknownSymbolIsNamedOnce() {
    // Repeats would make the message noise rather than a list.
    let found = KokoroPhonemes.unsupported("a#b#c%", vocabulary: vocabulary)
    #expect(found == ["a", "#", "b", "c", "%"])
}

@Test func whitespaceIsNotAMissingPhoneme() {
    // Word gaps never reach the encoder, so reporting them would send people
    // hunting for a symbol that was never the problem.
    #expect(KokoroPhonemes.unsupported("tə  \n tə", vocabulary: vocabulary).isEmpty)
}

@Test func emptyPhonemesAreRejected() {
    // Not "silence": an empty string means the caller lost their input
    // somewhere, and a zero-length WAV would be a worse answer than an error.
    #expect(throws: (any Error).self) {
        try KokoroPhonemes.validate("   \n  ")
    }
}
