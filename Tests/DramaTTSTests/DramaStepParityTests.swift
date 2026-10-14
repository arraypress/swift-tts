//
//  DramaStepParityTests.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  The decode path, one frame at a time, against Python's teacher-forced
//  states: prefill the prompt as generation does, then feed Python's generated
//  frames back through single-row backbone steps and the tower's per-codebook
//  path, forcing each code and recording what the heads would have chosen.
//  Opt-in, like DramaParityTests: DRAMA_MODEL and DRAMA_REFERENCE.
//

import Foundation
import MLX
import MLXNN
import XCTest
@testable import DramaTTS

final class DramaStepParityTests: XCTestCase {

    func testSingleStepDecodeMatchesTeacherForcing() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let modelPath = environment["DRAMA_MODEL"], let referencePath = environment["DRAMA_REFERENCE"] else {
            throw XCTSkip("set DRAMA_MODEL and DRAMA_REFERENCE to run the step parity probe")
        }
        let pipeline = try await DramaPipeline(folder: URL(fileURLWithPath: modelPath))
        let network = pipeline.network
        for name in ["06-angry", "01-plain"] {
            let dump = try loadArrays(url: URL(fileURLWithPath: referencePath).appendingPathComponent("\(name).safetensors"))
            let (frames, systemRows) = try pipeline.frames(references: [], history: [],
                                                           target: DramaParityTests.lines[name]!)
            let generated = dump["generated"]!
            let begin = Int32(pipeline.configuration.semanticStartTokenID)
            let rows = concatenated([generated[0 ..< 1] + begin, generated], axis: 0).transposed().asType(.int32)
            let caches = pipeline.startCaches(frames, systemRows: systemRows,
                                              voice: DramaPipeline.VoiceState(references: []))
            var hidden = pipeline.prefill(frames, caches: caches, start: systemRows, stop: frames.dim(0))
            var frame = frames[(frames.dim(0) - 1)...].expandedDimensions(axis: 0)
            let promptRows = frames.dim(0)
            var cosines: [Float] = []
            var semanticAgree = 0
            var towerAgree = 0
            var towerTotal = 0
            for t in 0 ..< rows.dim(0) {
                let reference = dump["hidden"]![promptRows - 1 + t]
                let h = hidden.reshaped(-1).asType(.float32)
                cosines.append(((h * reference).sum() / (sqrt((h * h).sum()) * sqrt((reference * reference).sum())))
                    .item(Float.self))
                let logits = network.semanticHead(hidden[0..., 0]).asType(.float32)
                let top = pipeline.candidateIDs[argMax(logits, axis: -1)].item(Int32.self)
                if top == dump["sem_top1"]![promptRows - 1 + t].item(Int32.self) { semanticAgree += 1 }

                let next = rows[t]
                let forcedC0 = next[1].reshaped(1, 1)
                let semantic = network.tower.isSemantic(next[0].reshaped(1)).expandedDimensions(axis: 1)
                var codebook = 0
                let expected = dump["tower_top1"]![promptRows - 1 + t]
                _ = network.tower.residualCodes(hidden, c0: forcedC0, semantic: semantic, frame: frame,
                                                caches: caches.tower) { headLogits in
                    let choice = argMax(headLogits[0..., 0].asType(.float32), axis: -1).item(Int32.self)
                    if choice == expected[codebook].item(Int32.self) { towerAgree += 1 }
                    towerTotal += 1
                    codebook += 1
                    return next[1 + codebook].reshaped(1, 1)
                }
                frame = next.reshaped(1, 1, -1)
                hidden = network.backbone.model(embeddings: network.embed(frame), cache: caches.backbone)
                eval(hidden)
            }
            print(String(format: "%@ step path: hidden cosine mean %.6f min %.6f, semantic top-1 %.4f, tower top-1 %.4f (%d frames)",
                         name, cosines.reduce(0, +) / Float(cosines.count), cosines.min()!,
                         Float(semanticAgree) / Float(rows.dim(0)), Float(towerAgree) / Float(towerTotal), rows.dim(0)))
        }
    }
}
