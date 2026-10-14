//
//  KokoroLongTextTests.swift
//  KokoroTTS
//
//  Created by David Sherlock on 2026.
//
//  Kokoro refused anything past 510 phonemes — `phonemeSequenceTooLong(745)`
//  for a 144-word paragraph, in plain and audiobook mode alike. The engine
//  now cuts long text into pieces at sentence ends, then clause marks, then
//  spaces, and joins the audio.
//

import Foundation
import Testing
@testable import KokoroTTS

/// 144 words, 775 characters, 745 phonemes through FluidAudio's G2P.
let longParagraph = """
    The lighthouse stood at the end of a long stone pier, and every evening the keeper climbed its spiral \
    stairs to light the lamp. He had done this for thirty years, through storms that shook the glass and \
    calm nights when the sea lay flat as a mirror. The ships that passed never knew his name, but they \
    trusted the light. One winter the supply boat failed to arrive, and he rationed his oil carefully, \
    burning the lamp only in the darkest hours. When the boat finally came, the captain asked how he had \
    managed. The keeper smiled and said that a small light, kept steady, is worth more than a bright one \
    that goes out. The captain wrote those words in his log, and years later his daughter read them aloud \
    at the keeper's funeral, while the lamp still turned above the water.
    """

// MARK: - Cutting

@Test func shortTextIsOnePiece() {
    #expect(KokoroText.pieces("This is a test. That is the plan.") == ["This is a test. That is the plan."])
    #expect(KokoroText.pieces("  \n ") == [])
}

@Test func aLongParagraphIsCutAtSentenceEnds() {
    let pieces = KokoroText.pieces(longParagraph)
    #expect(pieces.count == 3)
    #expect(pieces.allSatisfy { $0.count <= KokoroText.pieceCharacters })
    #expect(pieces.allSatisfy { $0.hasSuffix(".") }, "every cut is at a full stop: \(pieces)")
    #expect(pieces.joined(separator: " ") == KokoroText.collapse(longParagraph), "nothing lost or reordered")
}

@Test func aLongSentenceIsCutAtClauses() {
    let sentence = Array(repeating: "the keeper climbed the stairs again, and", count: 12).joined(separator: " ") + " slept."
    let pieces = KokoroText.pieces(sentence, limit: 120)
    #expect(pieces.count > 1)
    #expect(pieces.allSatisfy { $0.count <= 120 })
    #expect(pieces.dropLast().allSatisfy { $0.hasSuffix(",") }, "\(pieces)")
    #expect(pieces.joined(separator: " ") == sentence)
}

@Test func runOnTextIsCutBetweenWords() {
    let words = Array(repeating: "lamp", count: 100).joined(separator: " ")
    let pieces = KokoroText.pieces(words, limit: 50)
    #expect(pieces.allSatisfy { $0.count <= 50 })
    #expect(pieces.allSatisfy { !$0.hasPrefix(" ") && !$0.hasSuffix(" ") })
    #expect(pieces.joined(separator: " ") == words)
}

@Test func closingQuotesStayWithTheirSentence() {
    let text = "He said, “Keep it steady.” Then he left. " + String(repeating: "The lamp turned. ", count: 30)
    let first = KokoroText.pieces(text, limit: 60).first
    #expect(first?.hasPrefix("He said, “Keep it steady.” Then he left.") == true)
}

@Test func anOverflowingPieceHalvesAtTheMarkNearestTheMiddle() throws {
    let (first, second) = try #require(KokoroText.halves("one two three, four five six seven, eight"))
    #expect(first == "one two three,")
    #expect(second == "four five six seven, eight")
    let (left, right) = try #require(KokoroText.halves("one two three four"))
    #expect(left == "one two" && right == "three four")
    #expect(KokoroText.halves("antidisestablishmentarianism") == nil)
}

// Spoken end to end, the paragraph is tested through `speak` (its
// SpeakTests run the binary): CoreML's Kokoro graphs crash inside the test
// runner ("shape for TensorData is not static") but load in a plain binary,
// as the CLAUDE.md records.
