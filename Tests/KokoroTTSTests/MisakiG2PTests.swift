//
//  MisakiG2PTests.swift
//  KokoroTTS
//
//  Created by David Sherlock on 2026.
//
//  FluidAudio's neural G2P read "is" as "ice" and "this" as "thighs" every
//  time (14–26 % word error on plain prose in a bake-off). Kokoro now reads
//  through a port of Misaki, its own front end. The rules are tested here
//  on a small lexicon; the real one, when it is on disk, is held against
//  Python Misaki 0.9.4's output for the bake-off's narration.
//

import Foundation
import Testing
@testable import KokoroTTS

/// A few real Misaki entries — enough to exercise every rule.
private let tiny = MisakiLexicon(
    gold: [
        "is": .plain("ɪz"), "this": .tagged(["DEFAULT": "ðɪs", "None": "ðˈɪs"]), "the": .plain("ði"),
        "to": .plain("tu"), "am": .plain("æm"), "a": .plain("ɐ"), "test": .plain("tˈɛst"),
        "apple": .plain("ˈæpᵊl"), "plan": .plain("plˈæn"), "it": .plain("ɪt"), "go": .plain("ɡˈO"),
        "read": .tagged(["DEFAULT": "ɹˈid", "VBD": "ɹˈɛd", "VBN": "ɹˈɛd", "VBP": "ɹˈɛd"]),
        "live": .tagged(["DEFAULT": "lˈIv", "VERB": "lˈɪv"]),
        "US": .tagged(["DEFAULT": "ˌʌs", "NOUN": nil]),
        "N": .plain("ˈɛn"), "H": .plain("ˈAʧ"), "S": .plain("ˈɛs"), "P": .plain("pˈi"), "M": .plain("ˈɛm"),
        "U": .plain("jˈu"), "A": .plain("ˈA"),
        "lamp": .plain("lˈæmp"), "plant": .plain("plˈænt"), "wait": .plain("wˈAt"), "watch": .plain("wˈɑʧ"),
        "stop": .plain("stˈɑp"), "need": .plain("nˈid"), "Maya": .plain("mˈIə"), "we": .plain("wi"),
        "brother": .plain("bɹˈʌðəɹ"), "water": .plain("wˈɔɾəɹ"),
    ],
    silver: [:],
    british: false
)

private let reader = MisakiG2P(lexicon: tiny)

private func phonemes(_ text: String, guesses: [String: String] = [:]) -> String {
    reader.read(text, guesses: guesses).phonemes
}

// MARK: - The bug

@Test func isIsNotIce() {
    // "ice" would be "Is" (Misaki's I = the vowel in "eye").
    #expect(phonemes("This is a test.") == "ðˌɪs ɪz ɐ tˈɛst.")
    #expect(phonemes("It is the plan.") == "ˌɪt ɪz ðə plˈæn.")
}

// MARK: - Context-dependent words

@Test func theBeforeAVowelIsThee() {
    #expect(phonemes("the apple") == "ði ˈæpᵊl")
    #expect(phonemes("the plan") == "ðə plˈæn")
}

@Test func toDependsOnTheNextSound() {
    #expect(phonemes("to go") == "tə ɡˈO")
    #expect(phonemes("to it") == "tʊ ɪt")
    #expect(phonemes("go to.") == "ɡˈO tu.")
}

@Test func thisAtTheEndOfAPhraseIsStressed() {
    #expect(phonemes("read this") == "ɹˈid ðɪs".replacingOccurrences(of: "ðɪs", with: "ðˈɪs"))
    #expect(phonemes("this plan") == "ðɪs plˈæn")
}

@Test func theWordBeforePicksTheSpelling() {
    #expect(phonemes("we live") == "wi lˈɪv")
    #expect(phonemes("to live") == "tə lˈɪv")
    #expect(phonemes("the live plan") == "ðə lˈIv plˈæn")
    #expect(phonemes("we had read it") .hasSuffix("ɹˈɛd ɪt"))
}

@Test func theArticleAndThePronoun() {
    #expect(phonemes("a plan") == "ɐ plˈæn")
    #expect(phonemes("I am") == "ˌI ˈæm".replacingOccurrences(of: "ˈæm", with: "æm"))
}

// MARK: - Spelling out

@Test func acronymsAreSpelled() {
    #expect(phonemes("the NHS") == "ði ˌɛnˌAʧˈɛs")
    // "US" starts with a "y" sound, so "the" stays "thuh".
    #expect(phonemes("the US plan") == "ðə jˌuˈɛs plˈæn")
}

@Test func dottedAbbreviationsAreSpelledAndKeepTheirFullStop() {
    #expect(phonemes("at nine p.m.") .hasSuffix("pˌiˈɛm."))
    #expect(phonemes("p.m. Then") .hasPrefix("pˌiˈɛm."))
    #expect(!phonemes("p.m. then").contains("."))
}

@Test func shoutingIsReadNotSpelled() {
    #expect(phonemes("THIS IS THE PLAN") == phonemes("this is the plan"))
}

// MARK: - Endings on a known stem

@Test func pluralsPastAndGerunds() {
    #expect(phonemes("lamps") == "lˈæmps")
    #expect(phonemes("watches") == "wˈɑʧᵻz")
    #expect(phonemes("brother's") == "bɹˈʌðəɹz")
    #expect(phonemes("watched") == "wˈɑʧt")
    // Misaki has no rule for a doubled consonant before -ed; the real
    // lexicon lists "stopped" itself.
    #expect(reader.read("stopped").unknown == ["stopped"])
    #expect(phonemes("needed") == "nˈidᵻd")
    #expect(phonemes("planted") == "plˈæntᵻd")
    #expect(phonemes("waited") == "wˈAɾᵻd".replacingOccurrences(of: "ɾ", with: "T"))
    #expect(phonemes("waiting") == "wˈAɾɪŋ".replacingOccurrences(of: "ɾ", with: "T"))
    #expect(phonemes("stopping") == "stˈɑpɪŋ")
}

@Test func flapsAreWrittenAsKokoroLearnedThem() {
    #expect(phonemes("water") == "wˈɔTəɹ")
}

// MARK: - Unknown words

@Test func unknownWordsAreReportedThenGuessed() {
    let first = reader.read("Siobhan is here.")
    #expect(first.unknown == ["Siobhan", "here"])
    let guessed = reader.read("Siobhan is here.", guesses: ["siobhan": "ʃɪvˈɔn", "here": "hˈɪɹ"])
    #expect(guessed.unknown.isEmpty)
    #expect(guessed.phonemes == "ʃɪvˈɔn ɪz hˈɪɹ.")
}

@Test func accentsFallBackToTheLexicon() {
    #expect(MisakiG2P.guessKey("Joaquín") == "joaquin")
    #expect(phonemes("Máya") == "mˈIə")
}

// MARK: - Punctuation

@Test func straightQuotesBecomeCurly() {
    #expect(phonemes("\"is it?\" we") == "“ɪz ɪt?” wi")
}

@Test func aSpacedHyphenIsADashAndAJoiningOneASpace() {
    #expect(phonemes("plan - test") == "plˈæn — tˈɛst")
    #expect(phonemes("lamp-test") == "lˈæmp tˈɛst")
}

// MARK: - Stress rules (Misaki's apply_stress)

@Test func stressRules() {
    #expect(MisakiG2P.applyStress("ˈæpᵊl", -2) == "æpᵊl")
    #expect(MisakiG2P.applyStress("ˈæpᵊl", -1) == "ˌæpᵊl")
    #expect(MisakiG2P.applyStress("ɪz", 0.5) == "ˌɪz")
    #expect(MisakiG2P.applyStress("ɪz", 2) == "ˈɪz")
    #expect(MisakiG2P.applyStress("pz", 2) == "pz")
    #expect(MisakiG2P.restress("ˈplæn") == "plˈæn")
}

// MARK: - The real lexicon, when it is installed

/// The bake-off's narration through Python Misaki 0.9.4 (`en.G2P(trf=False)`), 2026-10-15.
private let misakiNarration = "ðə lˈIthˌWs stˈʊd æt ði ˈɛʤ ʌv ði ˈIlənd, ɪts wˈIt pˈAnt lˈɔŋ sˈɪns wˈɔɹn tə ɡɹˈA "
    + "bI ðə sˈɔlt wˈɪnd. ˈɛvəɹi ˈivnɪŋ ðə kˈipəɹ klˈImd ðə spˈIɹəl stˈɛɹz, lˈɪt ðə lˈæmp, ænd wˈɑʧt ðə bˈim "
    + "swˈip slˈOli əkɹˈɔs ðə dˈɑɹk wˈɔTəɹ."

@Test(.enabled(if: FileManager.default.fileExists(
    atPath: KokoroFiles.textDirectory.appendingPathComponent("us_gold.json").path)))
func matchesPythonMisakiOnTheBakeOffNarration() throws {
    let real = MisakiG2P(lexicon: try MisakiLexicon.load(from: KokoroFiles.textDirectory, british: false))
    let text = "The lighthouse stood at the edge of the island, its white paint long since worn to grey by the "
        + "salt wind. Every evening the keeper climbed the spiral stairs, lit the lamp, and watched the beam "
        + "sweep slowly across the dark water."
    let reading = real.read(text)
    #expect(reading.unknown.isEmpty)
    #expect(reading.phonemes == misakiNarration)
    #expect(real.read("This is it. That is the plan.").phonemes == "ðˌɪs ɪz ɪt. ðˌæt ɪz ðə plˈæn.")
}
