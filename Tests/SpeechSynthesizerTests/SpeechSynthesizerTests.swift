//
//  SpeechSynthesizerTests.swift
//  SpeechSynthesizerTests
//

import XCTest
@testable import SpeechSynthesizer

final class SpeechSynthesizerTests: XCTestCase {

    // MARK: - SpokenAudio

    func testDuration_isSamplesOverSampleRate() {
        let audio = SpokenAudio(samples: Array(repeating: 0, count: 24_000), sampleRate: 24_000)
        XCTAssertEqual(audio.duration, 1.0, accuracy: 0.0001)
    }

    func testDuration_withZeroSampleRate_isZero() {
        XCTAssertEqual(SpokenAudio(samples: [0, 0], sampleRate: 0).duration, 0)
    }

    func testIsEmpty() {
        XCTAssertTrue(SpokenAudio(samples: []).isEmpty)
        XCTAssertFalse(SpokenAudio(samples: [0.1]).isEmpty)
    }

    func testWavData_hasValidRiffHeader() {
        let audio = SpokenAudio(samples: [0, 0.5, -0.5, 1.0], sampleRate: 24_000)
        let data = audio.wavData()

        func string(_ range: Range<Int>) -> String { String(decoding: data[range], as: UTF8.self) }
        XCTAssertEqual(string(0..<4), "RIFF")
        XCTAssertEqual(string(8..<12), "WAVE")
        XCTAssertEqual(string(12..<16), "fmt ")
        XCTAssertEqual(string(36..<40), "data")

        // 44-byte header + 2 bytes per 16-bit sample.
        XCTAssertEqual(data.count, 44 + audio.samples.count * 2)
    }

    func testWavData_encodesSampleRate() {
        let data = SpokenAudio(samples: [0], sampleRate: 22_050).wavData()
        // Sample rate is a little-endian UInt32 at byte offset 24.
        let rate = data[24..<28].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        XCTAssertEqual(rate, 22_050)
    }

    func testWavData_clampsOutOfRangeSamples() {
        // +2.0 and -2.0 must clamp to full-scale Int16, not overflow.
        let data = SpokenAudio(samples: [2.0, -2.0], sampleRate: 24_000).wavData()
        let first = data[44..<46].withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
        let second = data[46..<48].withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
        XCTAssertEqual(first, Int16.max)
        XCTAssertEqual(second, -Int16.max)
    }

    // MARK: - TTSModel metadata

    func testAllModels_areCommercialSafe() {
        for model in TTSModel.allCases {
            XCTAssertTrue(model.isCommercialUseAllowed, "\(model) should be commercial-safe")
            XCTAssertTrue(["Apache-2.0", "MIT"].contains(model.license), "\(model) has non-permissive license")
        }
    }

    func testRuntimeSplit_coreMLIsMobileMLXIsNot() {
        for model in TTSModel.allCases {
            switch model.runtime {
            case .coreML: XCTAssertTrue(model.runsOnMobile, "\(model) is CoreML but not mobile")
            case .mlx: XCTAssertFalse(model.runsOnMobile, "\(model) is MLX but marked mobile")
            }
        }
    }

    func testKokoro_isDefaultTierNoCloning() {
        XCTAssertEqual(TTSModel.kokoro.runtime, .coreML)
        XCTAssertTrue(TTSModel.kokoro.runsOnMobile)
        XCTAssertFalse(TTSModel.kokoro.supportsVoiceCloning)
    }

    func testCloningModels() {
        XCTAssertTrue(TTSModel.pocket.supportsVoiceCloning)
        XCTAssertTrue(TTSModel.chatterbox.supportsVoiceCloning)
        XCTAssertFalse(TTSModel.kokoro.supportsVoiceCloning)
    }

    // MARK: - SynthesisOptions

    func testRate_clampsToRange() {
        XCTAssertEqual(SynthesisOptions(rate: 10).rate, 4.0)
        XCTAssertEqual(SynthesisOptions(rate: 0.01).rate, 0.25)
        XCTAssertEqual(SynthesisOptions(rate: 1.5).rate, 1.5)
    }

    func testDefaults() {
        let options = SynthesisOptions()
        XCTAssertNil(options.voice)
        XCTAssertEqual(options.language, "en-US")
        XCTAssertEqual(options.rate, 1.0)
        XCTAssertEqual(options.sampleRate, 24_000)
    }

    // MARK: - Errors

    func testErrorDescriptions_arePresent() {
        XCTAssertNotNil(TTSError.notPrepared.errorDescription)
        XCTAssertNotNil(TTSError.modelDownloadFailed("net").errorDescription)
        XCTAssertNotNil(TTSError.unsupportedVoice("x").errorDescription)
    }
}
