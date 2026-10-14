//
//  DramaParityTests.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  Parity against the Python reference (mlx-audio's fish_drama3) on the same
//  inputs. Opt-in: it needs the 22 GB model and reference tensors dumped by the
//  Python implementation, so it runs only with both set —
//
//      DRAMA_MODEL=<model folder> DRAMA_REFERENCE=<dump folder> swift test --filter DramaParity
//
//  The dump holds, per probe line, the prompt frames Python built, and for two
//  lines a seeded generation with Python's teacher-forced hidden states, its
//  semantic and tower top-1 choices and its codec decode. Results go to
//  $DRAMA_REFERENCE/swift-parity.json.
//

import Foundation
import MLX
import MLXAudioCodecs
import MLXNN
import XCTest
@testable import DramaTTS

final class DramaParityTests: XCTestCase {

    func testParityWithPythonReference() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let modelPath = environment["DRAMA_MODEL"], let referencePath = environment["DRAMA_REFERENCE"] else {
            throw XCTSkip("set DRAMA_MODEL and DRAMA_REFERENCE to run the parity probe")
        }
        let reference = URL(fileURLWithPath: referencePath)
        let pipeline = try await DramaPipeline(folder: URL(fileURLWithPath: modelPath))
        var results: [String: Any] = [:]

        // Tokenizer: every segment string tokenizes to Python's ids.
        let tokens = try JSONSerialization.jsonObject(
            with: Data(contentsOf: reference.appendingPathComponent("tokens.json"))) as! [String: Any]
        let segments = tokens["segments"] as! [String]
        let ids = tokens["ids"] as! [[Int]]
        var tokenMatches = 0
        for (segment, expected) in zip(segments, ids) {
            let got = pipeline.tokens(segment)
            if got == expected { tokenMatches += 1 } else { print("token mismatch: \(segment.debugDescription)\n  \(got)\n  \(expected)") }
        }
        results["tokenizer_segments_matching"] = "\(tokenMatches)/\(segments.count)"
        XCTAssertEqual(tokenMatches, segments.count)

        let files = try FileManager.default.contentsOfDirectory(atPath: referencePath)
            .filter { $0.hasSuffix(".safetensors") }.sorted()
        var promptMatches = 0
        for file in files {
            let name = String(file.dropLast(".safetensors".count))
            let dump = try loadArrays(url: reference.appendingPathComponent(file))
            let text = Self.lines[name]!
            let (frames, systemRows) = try pipeline.frames(references: [], history: [], target: text)
            let same = frames.shape == dump["frames"]!.shape
                && (frames .== dump["frames"]!.asType(.int32)).all().item(Bool.self)
                && systemRows == Int(dump["system_rows"]![0].item(Int32.self))
            if same { promptMatches += 1 } else { print("prompt mismatch: \(name)") }

            guard let generated = dump["generated"] else { continue }
            results[name] = try deep(pipeline, frames: frames, dump: dump, generated: generated)
        }
        results["prompt_frames_matching"] = "\(promptMatches)/\(files.count)"
        XCTAssertEqual(promptMatches, files.count)

        let json = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: reference.appendingPathComponent("swift-parity.json"))
        print(String(decoding: json, as: UTF8.self))
    }

    /// Teacher-forced backbone, semantic head, tower and codec on Python's generation.
    private func deep(_ pipeline: DramaPipeline, frames: MLXArray, dump: [String: MLXArray],
                      generated: MLXArray) throws -> [String: Any] {
        let network = pipeline.network
        let begin = Int32(pipeline.configuration.semanticStartTokenID)
        let rows = concatenated([generated[0 ..< 1] + begin, generated], axis: 0).transposed().asType(.int32)
        let full = concatenated([frames, rows], axis: 0).expandedDimensions(axis: 0)
        let T = full.dim(1)

        let cache = network.backbone.model.makeCache()
        var pieces: [MLXArray] = []
        for start in stride(from: 0, to: T, by: 64) {
            let h = network.backbone.model(embeddings: network.embed(full[0..., start ..< min(start + 64, T)]),
                                           cache: cache)
            eval(h)
            pieces.append(h[0].asType(.float32))
        }
        let hidden = concatenated(pieces, axis: 0)
        let reference = dump["hidden"]!
        let cosine = (hidden * reference).sum(axis: -1)
            / (sqrt((hidden * hidden).sum(axis: -1)) * sqrt((reference * reference).sum(axis: -1)))
        let cosines = cosine.asArray(Float.self)

        let semantic = network.semanticHead(hidden.asType(.bfloat16)).asType(.float32)
        let semanticTop = pipeline.candidateIDs[argMax(semantic, axis: -1)].asType(.int32)
        let promptRows = frames.dim(0)
        // Only rows whose next token is generated audio (or EOS) are predictions.
        let predicted = (promptRows - 1) ..< T
        let semanticAgree = (semanticTop[predicted] .== dump["sem_top1"]![predicted]).asType(.float32).mean()
            .item(Float.self)
        let logitError = abs(semantic - dump["sem_logits"]!).max().item(Float.self)

        let towerCache = network.tower.makeCache()
        let towerTop = network.tower.teacherForcedTop1(hidden.asType(.bfloat16)[..<(T - 1)].expandedDimensions(axis: 0),
                                                       frames: full[0..., ..<(T - 1)], nextFrames: full[0..., 1...],
                                                       caches: towerCache)[0].asType(.int32)
        let towerRows = (promptRows - 1) ..< (T - 1)
        let towerAgree = (towerTop[towerRows] .== dump["tower_top1"]![towerRows]).asType(.float32).mean()
            .item(Float.self)

        // Codec: a whole decode, and the streamed overlap decode, against Python.
        let count = generated.dim(1)
        let (audio, _) = pipeline.codec.decode(generated.expandedDimensions(axis: 0),
                                               featureLengths: MLXArray([Int32(count)]))
        let whole = audio.reshaped(-1).asType(.float32)
        let pythonAudio = dump["audio"]!
        let frameList = (0 ..< count).map { generated[0..., $0] }
        var streamed: [Float] = []
        var decoded = 0
        let stream = CodecStream(codec: pipeline.codec)
        while decoded < count {
            let upTo = min(count, decoded + 16)
            streamed += pipeline.decode(Array(frameList[..<upTo]), from: decoded, stream: stream)
            decoded = upTo
        }
        let streamedArray = MLXArray(streamed)
        func snr(_ a: MLXArray, _ b: MLXArray) -> Float {
            let n = min(a.dim(0), b.dim(0))
            let signal = (b[..<n] * b[..<n]).sum().item(Float.self)
            let noise = ((a[..<n] - b[..<n]) * (a[..<n] - b[..<n])).sum().item(Float.self)
            return 10 * log10(signal / max(noise, 1e-20))
        }
        let firstMismatch = cosines.firstIndex { $0 < 0.99 }
        return [
            "rows": T, "prompt_rows": promptRows, "generated_frames": count,
            "hidden_cosine_min": cosines.min()!, "hidden_cosine_mean": cosines.reduce(0, +) / Float(cosines.count),
            "hidden_first_row_below_0.99": firstMismatch.map { $0 as Any } ?? "none",
            "semantic_top1_agreement": semanticAgree, "semantic_logit_max_abs_error": logitError,
            "tower_top1_agreement": towerAgree,
            "codec_whole_vs_python_snr_db": snr(whole, pythonAudio),
            "codec_whole_vs_python_max_abs": abs(whole - pythonAudio[..<whole.dim(0)]).max().item(Float.self),
            "codec_streamed_vs_python_snr_db": snr(streamedArray, pythonAudio),
            "codec_samples": [whole.dim(0), pythonAudio.dim(0), streamed.count],
        ]
    }

    static let lines: [String: String] = [
        "01-plain": "The train to Edinburgh is running about twenty minutes late, so grab a coffee and settle in.",
        "02-brackets-stressed": "[stressed] The train to Edinburgh is running about twenty minutes late, and I have a meeting at nine.",
        "03-braces-stressed": "{feeling stressed} The train to Edinburgh is running about twenty minutes late, and I have a meeting at nine.",
        "04-whisper-laugh": "[whispering] Don't tell anyone, but I ate the last slice of cake. [laughs] It was worth it.",
        "05-midline": "I opened the letter, read the first line, and [shaky breath] I just had to sit down.",
        "06-angry": "[angry] I have asked you three times to stop leaving the door open!",
        "07-dialogue": "<|speaker:0|> Are you coming to the party tonight? <|speaker:1|> [sighs] I'd love to, but I'm completely exhausted. <|speaker:0|> [laughs] Come on, just for an hour!",
        "08-spanish": "[happy] ¡Hoy es un día precioso para dar un paseo por el parque!",
    ]
}
