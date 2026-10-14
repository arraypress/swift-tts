//
//  OmniVoiceModelTests.swift
//  OmniVoiceTTS
//
//  Created by David Sherlock on 2026.
//
//  Runs the real model, so it is opt-in: point OMNIVOICE_MODEL at a folder
//  holding mlx-community/OmniVoice and run
//
//      OMNIVOICE_MODEL=<folder> swift test --filter OmniVoiceModelTests
//
//  Without it every test skips.
//

import Foundation
import SpeechSynthesizer
import XCTest
@testable import OmniVoiceTTS

final class OmniVoiceModelTests: XCTestCase {

    private func engine() async throws -> OmniVoiceEngine {
        guard let path = ProcessInfo.processInfo.environment["OMNIVOICE_MODEL"] else {
            throw XCTSkip("set OMNIVOICE_MODEL to a model folder to run the model")
        }
        let engine = try OmniVoiceEngine(modelDirectory: URL(fileURLWithPath: path), licence: OmniVoiceLicence.version)
        try await engine.prepare()
        return engine
    }

    func testSameDesignAndSeedRepeatExactly() async throws {
        let engine = try await engine()
        let settings = OmniVoiceSettings(voiceDesign: "male, elderly, low pitch, british accent", seed: 1, steps: 16)
        let first = try await engine.synthesize("The quarterly review is ready.", settings: settings).audio
        let second = try await engine.synthesize("The quarterly review is ready.", settings: settings).audio
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first.samples, second.samples)
        XCTAssertGreaterThan(first.duration, 1)
        XCTAssertLessThan(first.duration, 6)
    }

    func testLongTextStreamsInPieces() async throws {
        let engine = try await engine()
        let text = String(repeating: "The committee met on Tuesday to review the budget for the coming year. ", count: 12)
        var pieces = 0
        var report: OmniVoiceReport?
        for try await chunk in engine.chunks(text, settings: OmniVoiceSettings(seed: 3, steps: 16)) {
            if chunk.isFinal { report = chunk.report } else { pieces += 1 }
        }
        XCTAssertGreaterThan(pieces, 1)
        XCTAssertEqual(report?.chunks, pieces)
    }
}
