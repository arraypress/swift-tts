//
//  OmniVoiceRulesTests.swift
//  OmniVoiceTTS
//
//  Created by David Sherlock on 2026.
//
//  The engine's own rules — the licence and memory gates, the voice-design
//  vocabulary, tag filtering, language codes, chunking, audio clean-up —
//  none of which needs the model.
//

import Foundation
import SpeechSynthesizer
import XCTest
@testable import OmniVoiceTTS

final class OmniVoiceRulesTests: XCTestCase {

    // MARK: Licence and memory

    func testEngineRefusesWithoutTheLicenceVersion() {
        XCTAssertThrowsError(try OmniVoiceEngine(modelDirectory: URL(fileURLWithPath: "/tmp"), licence: "yes",
                                                 physicalMemory: 64 << 30)) { error in
            XCTAssertEqual(error as? OmniVoiceError, .licenceNotAccepted(expected: OmniVoiceLicence.version))
        }
    }

    func testEngineRefusesASmallMac() {
        XCTAssertThrowsError(try OmniVoiceEngine(modelDirectory: URL(fileURLWithPath: "/tmp"),
                                                 licence: OmniVoiceLicence.version, physicalMemory: 8 << 30)) { error in
            XCTAssertEqual(error as? OmniVoiceError, .insufficientMemory(physicalGB: 8, requiredGB: 16))
        }
        XCTAssertNoThrow(try OmniVoiceEngine(modelDirectory: URL(fileURLWithPath: "/tmp"),
                                             licence: OmniVoiceLicence.version, physicalMemory: 16 << 30))
    }

    func testModelIsOptInAndNotCommercialSafe() {
        XCTAssertFalse(TTSModel.omnivoice.isCommercialUseAllowed)
        XCTAssertTrue(TTSModel.omnivoice.hasLicenseRestrictions)
        XCTAssertTrue(TTSModel.omnivoice.supportsVoiceCloning)
        XCTAssertEqual(TTSModel.omnivoice.runtime, .mlx)
    }

    func testLicenceCarriesTheRequiredAttributionAndBothTexts() {
        XCTAssertTrue(OmniVoiceLicence.attribution.hasPrefix("Built with Higgs Materials licensed from Boson AI"))
        XCTAssertTrue(OmniVoiceLicence.summary.contains(OmniVoiceLicence.attribution))
        XCTAssertTrue(OmniVoiceLicence.notice.contains("Meta Llama 3 is licensed under the Meta Llama 3 Community License"))
        XCTAssertTrue(OmniVoiceLicence.higgsAudioLicenceText.hasPrefix("BOSON HIGGS AUDIO 2 COMMUNITY LICENSE AGREEMENT"))
        XCTAssertTrue(OmniVoiceLicence.llama3LicenceText.hasPrefix("META LLAMA 3 COMMUNITY LICENSE AGREEMENT"))
        XCTAssertTrue(OmniVoiceLicence.summary.contains("CC BY-NC"))
    }

    // MARK: Voice design

    func testValidDesignIsNormalisedNotRewritten() throws {
        XCTAssertEqual(try VoiceDesignVocabulary.resolve("Male, Elderly, LOW PITCH, British Accent"),
                       "male, elderly, low pitch, british accent")
        XCTAssertEqual(try VoiceDesignVocabulary.resolve(" female ,whisper ,"), "female, whisper")
        XCTAssertNil(try VoiceDesignVocabulary.resolve(" , "))
    }

    func testFreeTextIsRefusedWithTheVocabulary() {
        XCTAssertThrowsError(try VoiceDesignVocabulary.resolve("warm older British man")) { error in
            guard case .invalidVoiceDesign(let message) = error as? OmniVoiceError else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("'warm older British man'"))
            XCTAssertTrue(message.contains("pitch: very low pitch, low pitch"))
            XCTAssertTrue(message.contains("british accent"))
        }
    }

    func testATypoGetsASuggestion() {
        XCTAssertThrowsError(try VoiceDesignVocabulary.resolve("male, britsh accent")) { error in
            guard case .invalidVoiceDesign(let message) = error as? OmniVoiceError else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("did you mean 'british accent'?"), message)
        }
        XCTAssertThrowsError(try VoiceDesignVocabulary.resolve("old"))   // no close match
    }

    func testOneItemPerCategory() {
        XCTAssertThrowsError(try VoiceDesignVocabulary.resolve("male, female")) { error in
            guard case .invalidVoiceDesign(let message) = error as? OmniVoiceError else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("Pick one gender"), message)
        }
        XCTAssertThrowsError(try VoiceDesignVocabulary.resolve("low pitch, very high pitch"))
        XCTAssertThrowsError(try VoiceDesignVocabulary.resolve("british accent, 四川话"))
    }

    func testChineseTextOrADialectTurnsTheDesignChinese() throws {
        XCTAssertEqual(try VoiceDesignVocabulary.resolve("female, young adult", text: "今天天气很好"), "女，青年")
        XCTAssertEqual(try VoiceDesignVocabulary.resolve("male, 四川话"), "男，四川话")
        // An English accent keeps it English even over Chinese text.
        XCTAssertEqual(try VoiceDesignVocabulary.resolve("male, british accent", text: "今天"), "male, british accent")
        XCTAssertEqual(try VoiceDesignVocabulary.resolve("女，老年"), "female, elderly")
    }

    func testVocabularyMatchesTheReference() {
        // 2 + 5 + 5 + 1 + 10 accents in English, 2 + 5 + 5 + 1 + 12 dialects in Chinese.
        XCTAssertEqual(VoiceDesignVocabulary.allItems.count, 23 + 25)
    }

    // MARK: Tags

    func testSupportedTagsAndPronunciationsPass() {
        let text = "[laughter] You got me. He plays the [B EY1 S] guitar. [sigh] Fine."
        let filtered = OmniTags.filter(text)
        XCTAssertEqual(filtered.text, text)
        XCTAssertEqual(filtered.dropped, [])
    }

    func testOtherCuesAreRemovedAndReported() {
        let filtered = OmniTags.filter("[whispers] Do not tell {feeling stressed} anyone <|speaker:1|> about [Laughter] this.")
        XCTAssertEqual(filtered.text, "Do not tell anyone about this.")
        XCTAssertEqual(filtered.dropped, ["[whispers]", "{feeling stressed}", "<|speaker:1|>", "[Laughter]"])
    }

    func testLowercaseOrEmptyBracketsAreNotPronunciations() {
        XCTAssertFalse(OmniTags.isPronunciation("b ey1 s"))
        XCTAssertFalse(OmniTags.isPronunciation(""))
        XCTAssertFalse(OmniTags.isPronunciation("NOTE 5"))
        XCTAssertTrue(OmniTags.isPronunciation("K AH0 L ER1"))
    }

    func testUnclosedBracketsAreText() {
        XCTAssertEqual(OmniTags.filter("a [b and c").text, "a [b and c")
        XCTAssertEqual(OmniTags.filter("x < y | z").text, "x < y | z")
    }

    func testQuestionTagsMoveBeforeAClosingQuestionMark() {
        let measured = "You are leaving already [question-en]?"
        for written in ["You are leaving already [question-en]",          // broke 2/4
                        "You are leaving already? [question-en]",         // broke 4/4
                        "You are leaving already. [question-en]",         // broke 4/4
                        "[question-en] You are leaving already?",         // broke 3/4
                        "You are leaving already [question-en]?"] {       // broke 0/4
            XCTAssertEqual(OmniTags.filter(written).text, measured, written)
        }
        XCTAssertEqual(OmniTags.filter(measured).moved, [], "already where it works")
        XCTAssertEqual(OmniTags.filter("You are leaving already? [question-en]").moved, ["[question-en]"])
    }

    func testQuestionTagsLineByLineAndAcrossSentences() {
        XCTAssertEqual(OmniTags.filter("Hello there. So you finished it [question-ah]\nNext line.").text,
                       "Hello there. So you finished it [question-ah]?\nNext line.")
        XCTAssertEqual(OmniTags.filter("Fine. [question-oh] You did it.").text, "Fine. You did it [question-oh]?")
    }

    func testOtherTagsStayWhereTheyAre() {
        XCTAssertEqual(OmniTags.filter("You are leaving already [question-en] so soon?").text,
                       "You are leaving already [question-en] so soon?", "words after it: measured fine")
        XCTAssertEqual(OmniTags.filter("Right, that is settled then [confirmation-en]").text,
                       "Right, that is settled then [confirmation-en]")
        XCTAssertEqual(OmniTags.filter("[laughter] You got me.").text, "[laughter] You got me.")
        XCTAssertEqual(OmniTags.filter("Oh [surprise-oh] that is big.").text, "Oh [surprise-oh] that is big.")
    }

    // MARK: Languages

    func testLanguagesResolveFromCodesNamesAndTags() throws {
        XCTAssertEqual(try OmniLanguages.resolve("en"), "en")
        XCTAssertEqual(try OmniLanguages.resolve("en-US"), "en")
        XCTAssertEqual(try OmniLanguages.resolve("pt_BR"), "pt")
        XCTAssertEqual(try OmniLanguages.resolve("English"), "en")
        XCTAssertEqual(try OmniLanguages.resolve("Cantonese"), "yue")
        XCTAssertEqual(try OmniLanguages.resolve("ar"), "arb")       // via "standard arabic"
        XCTAssertEqual(try OmniLanguages.resolve("welsh"), "cy")
        XCTAssertGreaterThanOrEqual(OmniLanguages.count, 600)
    }

    func testUnknownLanguageIsAnError() {
        XCTAssertThrowsError(try OmniLanguages.resolve("klingon")) { error in
            XCTAssertEqual(error as? OmniVoiceError, .unsupportedLanguage("klingon"))
        }
    }

    // MARK: Chunking

    func testShortTextIsOnePiece() {
        XCTAssertEqual(OmniText.chunks("Hello there.\nHow are you?"), ["Hello there. How are you?"])
    }

    func testLongTextSplitsAtSentencesIntoAboutFifteenSeconds() {
        let sentence = "The committee met on Tuesday to review the budget for the coming year. "
        let text = String(repeating: sentence, count: 20)
        XCTAssertGreaterThan(OmniText.estimatedSeconds(text), 30)
        let pieces = OmniText.chunks(text)
        XCTAssertGreaterThan(pieces.count, 2)
        for piece in pieces {
            XCTAssertTrue(piece.hasSuffix("."), piece)
            XCTAssertLessThan(OmniText.estimatedSeconds(piece), 22, piece)
        }
        XCTAssertEqual(pieces.joined(separator: " "), OmniText.flatten(text))
    }

    func testAbbreviationsDoNotEndASentence() {
        let pieces = OmniText.chunkAtPunctuation("Mr. Smith met Dr. Jones. They talked.", length: 10, minimumLength: 3)
        XCTAssertEqual(pieces, ["Mr. Smith met Dr. Jones.", "They talked."])
    }

    func testPunctuationAfterASplitJoinsThePreviousSentence() {
        XCTAssertEqual(OmniText.chunkAtPunctuation("Wait!\" she said.", length: 3, minimumLength: nil),
                       ["Wait!\"", "she said."])
    }

    func testThaiAndKhmerCarryACaveat() {
        XCTAssertNotNil(OmniText.tokenizerCaveat("วันนี้อากาศดีมาก"))
        XCTAssertNotNil(OmniText.tokenizerCaveat("ថ្ងៃនេះ"))
        XCTAssertNil(OmniText.tokenizerCaveat("今天天气很好 and English"))
    }

    func testTranscriptGetsEndPunctuation() {
        XCTAssertEqual(OmniText.punctuated("I left early"), "I left early.")
        XCTAssertEqual(OmniText.punctuated("Really?"), "Really?")
        XCTAssertEqual(OmniText.punctuated("我们走吧"), "我们走吧。")
    }

    func testPlanReportsWhatTheModelWillGet() throws {
        let plan = try OmniVoiceEngine.plan("[whispers] Hi [laughter]",
                                            settings: OmniVoiceSettings(voiceDesign: "Female", language: "en-GB"))
        XCTAssertEqual(plan.pieces, ["Hi [laughter]"])
        XCTAssertEqual(plan.voiceDesign, "female")
        XCTAssertEqual(plan.language, "en")
        XCTAssertEqual(plan.droppedTags, ["[whispers]"])
        XCTAssertEqual(plan.movedTags, [])
    }

    // MARK: Audio

    func testLongPausesAreCutToASecondAndEdgesTrimmed() {
        let rate = 1_000.0
        let tone = (0..<500).map { Float(sin(Double($0) * 0.3)) * 0.5 }
        let samples = [Float](repeating: 0, count: 700) + tone + [Float](repeating: 0, count: 3_000) + tone
            + [Float](repeating: 0, count: 900)
        let tight = OmniAudio.tightened(samples, sampleRate: rate)
        // 100 ms lead + tone + 1 s pause + tone + 100 ms trail.
        XCTAssertEqual(tight.count, 100 + 500 + 1_000 + 500 + 100)
    }

    func testShortPausesSurvive() {
        let rate = 1_000.0
        let tone = (0..<300).map { Float(sin(Double($0) * 0.3)) * 0.5 }
        let samples = tone + [Float](repeating: 0, count: 600) + tone
        XCTAssertEqual(OmniAudio.tightened(samples, sampleRate: rate).count, samples.count)
    }

    func testSilenceIsEmpty() {
        XCTAssertEqual(OmniAudio.tightened([Float](repeating: 0, count: 5_000), sampleRate: 1_000), [])
        XCTAssertEqual(OmniAudio.finished([Float](repeating: 0, count: 5_000), sampleRate: 1_000, isFirst: true), [])
    }

    func testPiecesArePaddedForJoining() {
        let rate = 1_000.0
        let tone = (0..<400).map { Float(sin(Double($0) * 0.3)) * 0.5 }
        let first = OmniAudio.finished(tone, sampleRate: rate, isFirst: true)
        let later = OmniAudio.finished(tone, sampleRate: rate, isFirst: false)
        XCTAssertEqual(first.count, 100 + 400 + 100)
        XCTAssertEqual(later.count, 400 + 100)
        XCTAssertEqual(first.first, 0)
        XCTAssertEqual(later.first ?? 1, 0, accuracy: 1e-6)   // faded in
    }

    func testReferenceIsCutToWholeFrames() {
        XCTAssertEqual(OmniVoiceEngine.wholeFrames([Float](repeating: 0.1, count: 2_000)).count, 1_920)
    }

    func testResamplingKeepsDuration() throws {
        let audio = SpokenAudio(samples: (0..<44_100).map { Float(sin(Double($0) * 0.05)) }, sampleRate: 44_100)
        let converted = try XCTUnwrap(audio.resampled(to: 24_000))
        XCTAssertEqual(converted.sampleRate, 24_000)
        XCTAssertEqual(Double(converted.samples.count), 24_000, accuracy: 50)
    }

    // MARK: Model folder

    func testMissingFilesAreNamed() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("omni-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertEqual(OmniModelFolder.missingFile(in: folder), "config.json")
        XCTAssertFalse(OmniModelFolder.canEncodeReferences(in: folder))
    }

    func testSemanticEncoderIsReadFromTheHeader() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("omni-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("audio_tokenizer"),
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func write(_ header: String) throws {
            var data = Data()
            var length = UInt64(header.utf8.count).littleEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
            data.append(contentsOf: header.utf8)
            try data.write(to: folder.appendingPathComponent("audio_tokenizer/model.safetensors"))
        }
        try write(#"{"semantic_model.encoder.weight":{"dtype":"F32","shape":[1],"data_offsets":[0,4]}}"#)
        XCTAssertTrue(OmniModelFolder.canEncodeReferences(in: folder))
        try write(#"{"acoustic_encoder.weight":{"dtype":"BF16","shape":[1],"data_offsets":[0,2]}}"#)
        XCTAssertFalse(OmniModelFolder.canEncodeReferences(in: folder))
    }
}

final class OmniVoiceTextTests: XCTestCase {

    func testTagsAreTheirOwnSegments() {
        XCTAssertEqual(TagAwareTokenizer.segments("<|text_start|>You got me. [laughter] I didn't see it.<|text_end|>"),
                       ["<|text_start|>You got me. ", "[laughter]", " I didn't see it.<|text_end|>"])
        XCTAssertEqual(TagAwareTokenizer.segments("[sigh][sigh]"), ["[sigh]", "[sigh]"])
        XCTAssertEqual(TagAwareTokenizer.segments("no tags [here]"), ["no tags [here]"])
    }

    func testChineseLosesItsSpaces() {
        XCTAssertEqual(OmniText.flatten("今天 天气 很好, ok\n（好）"), "今天天气很好, ok (好)")
    }
}
