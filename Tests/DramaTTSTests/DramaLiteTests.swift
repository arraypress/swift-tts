//
//  DramaLiteTests.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  The lite conversion on a two-layer stand-in checkpoint: which layers
//  change, that the new bits land in config.json and the shards, that the
//  stamp marks a finished folder, and that a lite folder starts on 32 GB.
//

import Foundation
import MLX
import XCTest
@testable import DramaTTS

final class DramaLiteTests: XCTestCase {

    func testPlanTouchesOnlyWhatItNames() {
        let plan = DramaLitePlan.lite
        XCTAssertEqual(plan.bits(forLayer: "backbone.model.layers.0.mlp.switch_mlp.up_proj", storedBits: 4), 3)
        XCTAssertEqual(plan.bits(forLayer: "backbone.model.layers.0.mlp.switch_mlp.down_proj", storedBits: 4), 3)
        XCTAssertNil(plan.bits(forLayer: "backbone.model.layers.0.linear_attn.out_proj", storedBits: 8))
        XCTAssertNil(plan.bits(forLayer: "backbone.model.layers.0.mlp.switch_mlp.up_proj", storedBits: 2), "never more bits")
        let mixed = DramaLitePlan(expertBits: 2, expertDownBits: 3, denseBits: 4)
        XCTAssertEqual(mixed.bits(forLayer: "x.switch_mlp.gate_proj", storedBits: 4), 2)
        XCTAssertEqual(mixed.bits(forLayer: "x.switch_mlp.down_proj", storedBits: 4), 3)
        XCTAssertEqual(mixed.bits(forLayer: "tower.layers.0.attention.wqkv", storedBits: 8), 4)
    }

    func testConversionRewritesExpertsAndStampsTheFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("drama-lite-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source"), target = root.appendingPathComponent("lite")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let expert = "backbone.model.layers.0.mlp.switch_mlp.up_proj"
        let dense = "backbone.model.layers.0.linear_attn.out_proj"
        let w = sin(MLXArray(0 ..< 2048).asType(.float32).reshaped(2, 8, 128) * 0.37)
        let (eq, es, eb) = quantized(w, groupSize: 64, bits: 4)
        let (dq, ds, db) = quantized(cos(MLXArray(0 ..< 1024).asType(.float32).reshaped(8, 128) * 0.11), groupSize: 64, bits: 8)
        try save(arrays: ["\(expert).weight": eq, "\(expert).scales": es, "\(expert).biases": eb!,
                          "\(dense).weight": dq, "\(dense).scales": ds, "\(dense).biases": db!,
                          "backbone.model.norm.weight": MLXArray.ones([128])],
                 url: source.appendingPathComponent("model-00001.safetensors"))
        let config: [String: Any] = ["quantization": ["group_size": 64, "bits": 8, expert: ["group_size": 64, "bits": 4]],
                                     "text_config": [:]]
        try JSONSerialization.data(withJSONObject: config).write(to: source.appendingPathComponent("config.json"))
        try Data("Fish Audio notice".utf8).write(to: source.appendingPathComponent("NOTICE"))
        try Data("tokenizer".utf8).write(to: source.appendingPathComponent("tokenizer.json"))

        try DramaLiteConversion.convert(from: source, to: target, plan: .lite, sourceRevision: "test@1")

        let out = try loadArrays(url: target.appendingPathComponent("model-00001.safetensors"))
        // 3 bits pack 32 values into 3 uint32s; 4 bits into 4: the weight shrank by 3/4.
        XCTAssertEqual(out["\(expert).weight"]!.shape, [2, 8, 128 * 3 / 32])
        XCTAssertEqual(out["\(dense).weight"]!.shape, dq.shape, "dense layers untouched")
        let back = dequantized(out["\(expert).weight"]!, scales: out["\(expert).scales"]!, biases: out["\(expert).biases"],
                               groupSize: 64, bits: 3)
        let error = abs(back - w).mean().item(Float.self)
        XCTAssertLessThan(error, 0.25, "3-bit round trip stays close to the weights")
        let table = try JSONSerialization.jsonObject(with: Data(contentsOf: target.appendingPathComponent("config.json")))
            as! [String: Any]
        let entry = (table["quantization"] as! [String: Any])[expert] as! [String: Int]
        XCTAssertEqual(entry["bits"], 3)
        XCTAssertEqual(DramaLiteStamp.read(target)?.plan, .lite)
        XCTAssertEqual(DramaLiteStamp.read(target)?.source, "test@1")
        XCTAssertTrue(try String(contentsOf: target.appendingPathComponent("NOTICE"), encoding: .utf8).contains("re-quantised"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("tokenizer.json").path))
        XCTAssertNil(DramaLiteStamp.read(source))

        // A lite folder starts on a 32 GB Mac; the download needs 36.
        XCTAssertNoThrow(try DramaEngine(modelDirectory: target, licence: DramaLicence.version, physicalMemory: 32 << 30))
        XCTAssertThrowsError(try DramaEngine(modelDirectory: source, licence: DramaLicence.version, physicalMemory: 32 << 30))
        XCTAssertEqual(DramaEngine.minimumMemory(lite: true), 32 << 30)
    }
}
