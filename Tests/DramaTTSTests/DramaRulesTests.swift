//
//  DramaRulesTests.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  The engine's own rules — frame budget, the silence gate, the memory floor,
//  the licence gate, the prompt layout, the quantisation table — none of
//  which needs the model.
//

import Foundation
import SpeechSynthesizer
import XCTest
@testable import DramaTTS

final class DramaRulesTests: XCTestCase {

    // MARK: Licence and memory

    func testEngineRefusesWithoutTheLicenceVersion() {
        XCTAssertThrowsError(try DramaEngine(modelDirectory: URL(fileURLWithPath: "/tmp"), licence: "yes",
                                             physicalMemory: 64 << 30)) { error in
            XCTAssertEqual(error as? DramaError, .licenceNotAccepted(expected: DramaLicence.version))
        }
    }

    func testEngineAcceptsTheLicenceVersionOnABigMac() throws {
        let engine = try DramaEngine(modelDirectory: URL(fileURLWithPath: "/tmp"), licence: DramaLicence.version,
                                     physicalMemory: 36 << 30)
        XCTAssertEqual(engine.model, .drama)
    }

    func testEngineRefusesBelowTheMemoryFloor() {
        XCTAssertThrowsError(try DramaEngine(modelDirectory: URL(fileURLWithPath: "/tmp"),
                                             licence: DramaLicence.version, physicalMemory: 32 << 30)) { error in
            XCTAssertEqual(error as? DramaError, .insufficientMemory(physicalGB: 32, requiredGB: 36))
        }
    }

    func testLicenceSummaryNamesTheTerms() {
        for term in ["non-commercial", "US$500,000", "hosted", "consent", "Built with Fish Audio"] {
            XCTAssertTrue(DramaLicence.summary.contains(term), term)
        }
    }

    // MARK: Budget

    func testFrameBudgetScalesWithTextAndStopsAtTheReferenceCap() {
        XCTAssertEqual(FrameBudget.maxFrames(for: "Hello."), 64 + 4 * 6)
        XCTAssertEqual(FrameBudget.maxFrames(for: String(repeating: "a", count: 300)), 1024)
        // The runaway line: capped near 19 s rather than the reference's 47.6 s.
        let line = "[whispers] Don't tell anyone, but I ate the last slice of cake. [laughs] It was worth it."
        XCTAssertLessThan(FrameBudget.maxFrames(for: line), 450)
    }

    // MARK: Silence

    func testQuietGatePassesSpeechAndHoldsPauses() {
        var gate = QuietGate(rule: SilenceRule(), sampleRate: 100)
        let speech = [Float](repeating: 0.1, count: 50)   // −20 dBFS
        let pause = [Float](repeating: 0.001, count: 50)  // −60 dBFS
        XCTAssertEqual(gate.pass(speech).emit.count, 50)
        XCTAssertEqual(gate.pass(pause).emit.count, 0)
        let resumed = gate.pass(speech)
        XCTAssertEqual(resumed.emit.count, 100, "a pause goes out with the speech after it")
        XCTAssertFalse(resumed.stop)
    }

    func testQuietGateStopsAfterTwoSecondsAndKeepsHalfASecond() {
        var gate = QuietGate(rule: SilenceRule(), sampleRate: 100)
        let hiss = [Float](repeating: 0.003, count: 100)   // ≈ −50 dBFS, the runaway's level
        var stopped = false
        var emitted = 0
        for _ in 0 ..< 3 where !stopped {
            let result = gate.pass(hiss)
            emitted += result.emit.count
            stopped = result.stop
        }
        XCTAssertTrue(stopped)
        XCTAssertEqual(emitted, 50)
    }

    /// Noise at a fixed level: what a runaway chunk sounds like.
    private func hiss(level: Float, seconds: Double, rate: Double = 44_100) -> [Float] {
        var generator = SystemRandomNumberGenerator()
        let amplitude = pow(10, level / 20) * Float(3).squareRoot()
        return (0 ..< Int(seconds * rate)).map { _ in Float.random(in: -amplitude ... amplitude, using: &generator) }
    }

    /// Noise whose loudness rises and falls four times a second, like syllables.
    private func syllables(level: Float, seconds: Double, rate: Double = 44_100) -> [Float] {
        hiss(level: level, seconds: seconds, rate: rate).enumerated().map { index, sample in
            sample * Float(0.15 + abs(sin(Double(index) / rate * 4 * .pi)))
        }
    }

    func testSteadyHissIsDeadAirEvenAboveTheSilenceLevel() {
        let gate = QuietGate(rule: SilenceRule(), sampleRate: 44_100)
        XCTAssertTrue(gate.isDeadAir(hiss(level: -38, seconds: 0.74)), "the measured runaway hissed at −37…−45")
        XCTAssertTrue(gate.isDeadAir(hiss(level: -60, seconds: 0.74)))
    }

    func testQuietSpeechIsNotDeadAir() {
        let gate = QuietGate(rule: SilenceRule(), sampleRate: 44_100)
        XCTAssertFalse(gate.isDeadAir(syllables(level: -38, seconds: 0.74)), "a whisper rises and falls")
        XCTAssertFalse(gate.isDeadAir(hiss(level: -20, seconds: 0.74)), "loud is never dead air")
    }

    // MARK: Prompt

    func testPromptWithoutReferences() {
        let (segments, system) = DramaPrompt.segments(references: [PromptTurn<Int>](), history: [], target: "Hi.")
        XCTAssertEqual(system, 3)
        XCTAssertEqual(texts(segments), ["<|im_start|>system\n", "convert the provided text to speech", "<|im_end|>\n",
                                         "<|im_start|>user\n", "<|speaker:0|> Hi.", "<|im_end|>\n",
                                         "<|im_start|>assistant\n<|voice|>"])
    }

    func testPromptWithAReferenceAndHistory() {
        let (segments, system) = DramaPrompt.segments(references: [PromptTurn(text: "Hello there.", codes: 1)],
                                                      history: [PromptTurn(text: "First.", codes: 2)], target: "Next.")
        XCTAssertEqual(system, 5)
        XCTAssertEqual(texts(segments)[2], "\n\n[Reference 1]\nText: <|speaker:0|> Hello there.\nSpeech: ")
        guard case .audio(let codes) = segments[3] else { return XCTFail("reference audio expected") }
        XCTAssertEqual(codes, 1)
        guard case .audio(let history) = segments[9] else { return XCTFail("history audio expected") }
        XCTAssertEqual(history, 2)
    }

    private func texts(_ segments: [PromptSegment<Int>]) -> [String] {
        segments.map { segment in
            if case .text(let string) = segment { return string }
            return "<audio>"
        }
    }

    // MARK: Quantisation

    func testQuantizationTableReadsDefaultsAndOverrides() throws {
        let json = #"{"group_size": 64, "bits": 8, "a.b": {"group_size": 64, "bits": 4}}"#
        let table = try JSONDecoder().decode(QuantizationTable.self, from: Data(json.utf8))
        XCTAssertEqual(table.standard, .init(groupSize: 64, bits: 8))
        XCTAssertEqual(WeightLoading.setting(for: "a.b", table: table, hasScales: { _ in true }),
                       .init(groupSize: 64, bits: 4))
        XCTAssertEqual(WeightLoading.setting(for: "c", table: table, hasScales: { _ in true }),
                       .init(groupSize: 64, bits: 8))
        XCTAssertNil(WeightLoading.setting(for: "c", table: table, hasScales: { _ in false }))
    }
}
