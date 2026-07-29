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

    func testWav_encodeDecodeRoundTrips() throws {
        let original = SpokenAudio(samples: [0, 0.5, -0.5, 0.999, -0.999], sampleRate: 24_000)
        let decoded = try SpokenAudio(wav: original.wavData())
        XCTAssertEqual(decoded.sampleRate, 24_000)
        XCTAssertEqual(decoded.samples.count, original.samples.count)
        for (a, b) in zip(decoded.samples, original.samples) {
            XCTAssertEqual(a, b, accuracy: 1.0 / Float(Int16.max))   // 16-bit quantization
        }
    }

    func testWav_decodeRejectsGarbage() {
        XCTAssertThrowsError(try SpokenAudio(wav: Data([0, 1, 2, 3])))
    }

    // MARK: - TTSModel metadata

    func testAllModels_areCommercialSafe() {
        for model in TTSModel.allCases {
            XCTAssertTrue(model.isCommercialUseAllowed, "\(model) should be commercial-safe")
        }
        // Downloadable models carry either a permissive licence or, if not, must be flagged
        // as restricted. The set is no longer uniformly Apache/MIT — Supertonic is OpenRAIL-M,
        // which permits commercial use under conditions the others do not impose — so the
        // invariant worth holding is that anything outside Apache/MIT *says so*.
        for model in TTSModel.allCases where model.requiresDownload {
            let permissive = ["Apache-2.0", "MIT"].contains(model.license)
            XCTAssertEqual(
                permissive, !model.hasLicenseRestrictions,
                "\(model) is \(model.license) — hasLicenseRestrictions must reflect that"
            )
        }
    }

    func testRuntimeSplit_gpuIsNotMobile() {
        for model in TTSModel.allCases {
            switch model.runtime {
            case .system, .coreML: XCTAssertTrue(model.runsOnMobile, "\(model) should run on mobile")
            case .mlx: XCTAssertFalse(model.runsOnMobile, "\(model) is MLX/GPU but marked mobile")
            case .onnx: XCTAssertTrue(model.runsOnMobile, "\(model) is ONNX and light enough for mobile")
            }
        }
    }

    func testApple_isZeroDownloadSystemEngine() {
        XCTAssertEqual(TTSModel.apple.runtime, .system)
        XCTAssertFalse(TTSModel.apple.requiresDownload)
        XCTAssertEqual(TTSModel.apple.approximateSizeMB, 0)
        XCTAssertTrue(TTSModel.apple.runsOnMobile)
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

    // MARK: - AppleEngine

    func testAppleEngine_reportsAppleModelAndReady() async {
        let engine = AppleEngine()
        XCTAssertEqual(engine.model, .apple)
        let ready = await engine.isReady
        XCTAssertTrue(ready)
    }

    func testAppleEngine_emptyText_throwsEmptyText() async {
        let engine = AppleEngine()
        do {
            _ = try await engine.synthesize("   \n")
            XCTFail("expected emptyText")
        } catch let error as TTSError {
            XCTAssertEqual(error, .emptyText)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAppleEngine_exposesSystemVoices() async throws {
        let voices = try await AppleEngine().availableVoices()
        XCTAssertFalse(voices.isEmpty, "system should expose at least one voice")
        XCTAssertTrue(voices.allSatisfy { $0.model == .apple })
    }

    // MARK: - Errors

    func testErrorDescriptions_arePresent() {
        XCTAssertNotNil(TTSError.notPrepared.errorDescription)
        XCTAssertNotNil(TTSError.modelDownloadFailed("net").errorDescription)
        XCTAssertNotNil(TTSError.unsupportedVoice("x").errorDescription)
    }
}
