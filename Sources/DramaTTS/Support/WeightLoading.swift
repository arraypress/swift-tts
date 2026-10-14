//
//  WeightLoading.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  Loads the 4-bit checkpoint as it is: each layer that has `.scales` in the
//  shards is swapped for its quantised form (group size and bits from the
//  config's per-layer table, else its default), then every array is loaded
//  and checked — a missing or misshapen key is an error, not a silent zero.
//

import Foundation
import MLX
import MLXNN

/// Reads Drama 3's shards into a ``DramaNetwork``.
enum WeightLoading {

    /// Arrays the network owns; the codec's are loaded separately.
    static let keptPrefixes = ["backbone.", "semantic_head.", "tower."]

    /// The model shards in a folder, in order.
    static func shards(in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasPrefix("model") && $0.hasSuffix(".safetensors") }.sorted()
            .map { folder.appendingPathComponent($0) }
    }

    /// The quantisation for a layer path, or nil to leave it dense.
    static func setting(for path: String, table: QuantizationTable?,
                        hasScales: (String) -> Bool) -> QuantizationTable.Setting? {
        guard hasScales(path) else { return nil }
        guard let table else { return QuantizationTable.Setting(groupSize: 64, bits: 4) }
        return table.layers[path] ?? table.standard
    }

    /// Quantises and loads the network.
    static func load(_ network: DramaNetwork, from folder: URL, configuration: DramaConfiguration) throws {
        let files = shards(in: folder)
        guard !files.isEmpty else { throw DramaError.modelMissing("no model-*.safetensors in \(folder.path)") }
        var weights: [String: MLXArray] = [:]
        for file in files {
            let arrays: [String: MLXArray]
            do { arrays = try loadArrays(url: file) } catch {
                throw DramaError.modelMissing("\(file.lastPathComponent) is unreadable: \(error)")
            }
            for (key, value) in arrays where keptPrefixes.contains(where: key.hasPrefix) {
                weights[key] = value
            }
        }
        quantize(model: network, filter: { path, _ in
            setting(for: path, table: configuration.quantization, hasScales: { weights["\($0).scales"] != nil })
                .map { ($0.groupSize, $0.bits, .affine) }
        })
        do {
            try network.update(parameters: ModuleParameters.unflattened(weights), verify: .all)
        } catch {
            throw DramaError.unsupportedModel("the weights do not fit the network: \(error)")
        }
        eval(network.parameters())
    }
}
