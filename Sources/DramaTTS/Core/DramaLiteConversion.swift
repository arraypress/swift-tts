//
//  DramaLiteConversion.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  The lite tier is made ON THIS MAC from the checkpoint speak downloads:
//  each quantised layer the plan names is dequantised from its stored bits
//  and quantised again to fewer (plain round-to-nearest, MLX affine; no
//  calibration and no training), shard by shard, and written beside the
//  original as a complete model folder the engine loads like any other.
//  Nothing is uploaded: the Fish Audio Community License calls a re-quantised
//  model a Derivative Work, and making one for yourself needs no
//  redistribution. The folder carries the licence, a NOTICE that says what
//  was changed, and `LITE.json` naming the plan and the source.
//

import Foundation
import MLX

/// Which layers the lite tier stores in how many bits.
public struct DramaLitePlan: Sendable, Equatable, Codable {
    /// The routed experts' gate and up projections (4 in the download).
    public var expertBits: Int
    /// The routed experts' down projections (4 in the download).
    public var expertDownBits: Int
    /// Every other quantised layer — attention, shared experts, the tower, embeddings (8 in the
    /// download); nil keeps them.
    public var denseBits: Int?
    /// Weights per scale.
    public var groupSize: Int

    public init(expertBits: Int, expertDownBits: Int, denseBits: Int?, groupSize: Int = 64) {
        self.expertBits = expertBits
        self.expertDownBits = expertDownBits
        self.denseBits = denseBits
        self.groupSize = groupSize
    }

    /// What the lite tier uses: every routed expert at 3 bits, the rest as downloaded. Measured
    /// in the README: 2-bit experts cut the peak only to 19.3 GB and lost 5 of 20 clips to runaways.
    public static let lite = DramaLitePlan(expertBits: 3, expertDownBits: 3, denseBits: nil)

    enum CodingKeys: String, CodingKey {
        case expertBits = "expert_bits"
        case expertDownBits = "expert_down_bits"
        case denseBits = "dense_bits"
        case groupSize = "group_size"
    }

    /// The bits for a layer stored at `bits`, or nil to copy it as it is.
    func bits(forLayer path: String, storedBits: Int) -> Int? {
        let target: Int?
        if path.contains(".switch_mlp.") {
            target = path.hasSuffix(".down_proj") ? expertDownBits : expertBits
        } else {
            target = denseBits
        }
        guard let target, target < storedBits else { return nil }
        return target
    }
}

/// The stamp a lite folder carries.
public struct DramaLiteStamp: Sendable, Equatable, Codable {
    /// The format of this stamp.
    public var version: Int
    /// The plan the folder was made with.
    public var plan: DramaLitePlan
    /// The source checkpoint's revision.
    public var source: String

    public static let currentVersion = 1

    public init(plan: DramaLitePlan, source: String) {
        version = Self.currentVersion
        self.plan = plan
        self.source = source
    }

    /// The stamp in `folder`, if it is a finished lite folder.
    public static func read(_ folder: URL) -> DramaLiteStamp? {
        guard let data = FileManager.default.contents(atPath: folder.appendingPathComponent(fileName).path) else { return nil }
        return try? JSONDecoder().decode(DramaLiteStamp.self, from: data)
    }

    /// Written last, so a folder without it is unfinished.
    public static let fileName = "LITE.json"
}

/// Makes a lite model folder from the downloaded one.
public enum DramaLiteConversion {

    /// What the NOTICE adds (the Fish Audio Community License asks a Derivative Work to say how it changed).
    static func noticeAddition(_ plan: DramaLitePlan) -> String {
        """

        Changed on this computer by speak (swift-tts DramaTTS): the routed experts' gate and up
        projections were re-quantised from 4 to \(plan.expertBits) bits and their down projections to \
        \(plan.expertDownBits) bits\(plan.denseBits.map { ", every other quantised layer from 8 to \($0) bits" } ?? "")
        (MLX affine, groups of \(plan.groupSize), round to nearest, no training). The Fish Audio Materials
        attribution above applies to the original weights.
        """
    }

    /// Gigabytes the lite folder's model shards take, from the source shards' headers.
    public static func estimatedBytes(source: URL, plan: DramaLitePlan) throws -> Int64 {
        let table = try readQuantization(source)
        var total: Int64 = 0
        for shard in WeightLoading.shards(in: source) {
            for (key, size) in try SafetensorsHeader.sizes(of: shard) {
                let layer = layerPath(of: key)
                let stored = table.flatMap { $0.layers[layer] ?? $0.standard }?.bits ?? 0
                if let bits = plan.bits(forLayer: layer, storedBits: stored), key.hasSuffix(".weight") {
                    total += size * Int64(bits) / Int64(stored)
                } else {
                    total += size
                }
            }
        }
        return total
    }

    /// Converts `source` into `destination` (created; an unfinished one is replaced).
    /// `progress` gets 0…1 by shard.
    public static func convert(from source: URL, to destination: URL, plan: DramaLitePlan, sourceRevision: String,
                               progress: ((Double) -> Void)? = nil) throws {
        let fm = FileManager.default
        guard let table = try readQuantization(source) else {
            throw DramaError.unsupportedModel("the download is not quantised; there is nothing to make lite from")
        }
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        // Everything but the shards and config.json: cloned (APFS copies cost no space).
        let names = try fm.contentsOfDirectory(atPath: source.path)
        for name in names where !(name.hasPrefix("model") && name.hasSuffix(".safetensors"))
            && name != "config.json" && name != "NOTICE" && name != DramaLiteStamp.fileName && !name.hasPrefix(".") {
            try fm.copyItem(at: source.appendingPathComponent(name), to: destination.appendingPathComponent(name))
        }
        let notice = (try? String(contentsOf: source.appendingPathComponent("NOTICE"), encoding: .utf8)) ?? ""
        try Data((notice + noticeAddition(plan)).utf8).write(to: destination.appendingPathComponent("NOTICE"))

        var changed: [String: QuantizationTable.Setting] = [:]
        let shards = WeightLoading.shards(in: source)
        for (index, shard) in shards.enumerated() {
            let arrays: [String: MLXArray]
            do { arrays = try loadArrays(url: shard) } catch {
                throw DramaError.modelMissing("\(shard.lastPathComponent) is unreadable: \(error)")
            }
            var out: [String: MLXArray] = [:]
            for (key, value) in arrays {
                guard key.hasSuffix(".weight"), case let layer = layerPath(of: key),
                      let scales = arrays[layer + ".scales"] else {
                    if out[key] == nil { out[key] = value }
                    continue
                }
                let stored = table.layers[layer] ?? table.standard
                guard let bits = plan.bits(forLayer: layer, storedBits: stored.bits) else {
                    out[key] = value
                    continue
                }
                let dense = dequantized(value, scales: scales, biases: arrays[layer + ".biases"],
                                        groupSize: stored.groupSize, bits: stored.bits, dtype: .bfloat16)
                let (wq, newScales, newBiases) = quantized(dense, groupSize: plan.groupSize, bits: bits)
                eval(wq, newScales)
                if let newBiases { eval(newBiases) }
                out[key] = wq
                out[layer + ".scales"] = newScales
                if let newBiases { out[layer + ".biases"] = newBiases }
                changed[layer] = QuantizationTable.Setting(groupSize: plan.groupSize, bits: bits)
            }
            do {
                try save(arrays: out, metadata: ["format": "mlx"],
                         url: destination.appendingPathComponent(shard.lastPathComponent))
            } catch { throw DramaError.unsupportedModel("could not write \(shard.lastPathComponent): \(error)") }
            Memory.clearCache()
            progress?(Double(index + 1) / Double(shards.count))
        }

        try writeConfiguration(from: source, to: destination, changed: changed)
        let stamp = try JSONEncoder().encode(DramaLiteStamp(plan: plan, source: sourceRevision))
        try stamp.write(to: destination.appendingPathComponent(DramaLiteStamp.fileName))
    }

    /// `backbone.model.layers.0.mlp.switch_mlp.up_proj.weight` → `…up_proj`.
    static func layerPath(of key: String) -> String {
        for suffix in [".weight", ".scales", ".biases"] where key.hasSuffix(suffix) {
            return String(key.dropLast(suffix.count))
        }
        return key
    }

    /// config.json's `quantization` table, nil when the checkpoint is not quantised.
    static func readQuantization(_ folder: URL) throws -> QuantizationTable? {
        struct Root: Decodable { var quantization: QuantizationTable? }
        guard let data = FileManager.default.contents(atPath: folder.appendingPathComponent("config.json").path) else {
            throw DramaError.modelMissing("no config.json in \(folder.path)")
        }
        do { return try JSONDecoder().decode(Root.self, from: data).quantization } catch {
            throw DramaError.unsupportedModel("config.json: \(error)")
        }
    }

    /// config.json with the changed layers' entries in its `quantization` table; everything else as it was.
    static func writeConfiguration(from source: URL, to destination: URL,
                                   changed: [String: QuantizationTable.Setting]) throws {
        let data = try Data(contentsOf: source.appendingPathComponent("config.json"))
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var quantization = root["quantization"] as? [String: Any] else {
            throw DramaError.unsupportedModel("config.json has no quantization table")
        }
        for (layer, setting) in changed {
            quantization[layer] = ["group_size": setting.groupSize, "bits": setting.bits]
        }
        root["quantization"] = quantization
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try out.write(to: destination.appendingPathComponent("config.json"))
    }
}

/// Array names and byte sizes from a safetensors header, without reading the data.
enum SafetensorsHeader {
    static func sizes(of file: URL) throws -> [String: Int64] {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        guard let prefix = try handle.read(upToCount: 8), prefix.count == 8 else { return [:] }
        let length = prefix.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
        guard let header = try handle.read(upToCount: Int(length)),
              let json = try JSONSerialization.jsonObject(with: header) as? [String: Any] else { return [:] }
        var sizes: [String: Int64] = [:]
        for (key, value) in json where key != "__metadata__" {
            guard let entry = value as? [String: Any], let offsets = entry["data_offsets"] as? [Int64],
                  offsets.count == 2 else { continue }
            sizes[key] = offsets[1] - offsets[0]
        }
        return sizes
    }
}
