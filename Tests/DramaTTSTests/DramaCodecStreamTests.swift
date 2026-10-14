//
//  DramaCodecStreamTests.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  Whether the streamed codec decode matches Python's whole decode, piece size
//  by piece size. Opt-in: DRAMA_MODEL and DRAMA_LONG_CODES (a long
//  generation's codes and Python's decode of them).
//

import Foundation
import MLX
import MLXAudioCodecs
import XCTest
@testable import DramaTTS

final class DramaCodecStreamTests: XCTestCase {

    func testStreamedDecode() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let modelPath = environment["DRAMA_MODEL"], let codesPath = environment["DRAMA_LONG_CODES"] else {
            throw XCTSkip("set DRAMA_MODEL and DRAMA_LONG_CODES to run the codec stream probe")
        }
        let pipeline = try await DramaPipeline(folder: URL(fileURLWithPath: modelPath))
        let dump = try loadArrays(url: URL(fileURLWithPath: codesPath))
        let generated = dump["generated"]!
        let python = dump["audio"]!.asArray(Float.self)
        let frames = (0 ..< generated.dim(1)).map { generated[0..., $0] }
        for piece in [1, 16, 64] {
            var audio: [Float] = []
            var decoded = 0
            let stream = CodecStream(codec: pipeline.codec)
            let started = Date()
            while decoded < frames.count {
                let upTo = min(frames.count, decoded + piece)
                audio += pipeline.decode(Array(frames[..<upTo]), from: decoded, stream: stream)
                decoded = upTo
            }
            let seconds = Date().timeIntervalSince(started)
            var signal: Float = 0
            var noise: Float = 0
            for (a, b) in zip(audio, python) {
                signal += b * b
                noise += (a - b) * (a - b)
            }
            print(String(format: "streamed in %2d-frame pieces: SNR %.1f dB vs Python, %d/%d samples, %.2f s for %.1f s",
                         piece, 10 * log10(signal / max(noise, 1e-20)), audio.count, python.count, seconds,
                         Double(python.count) / 44_100))
        }
    }
}
