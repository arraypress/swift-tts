//
//  BackboneModel.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  The Qwen3.5-MoE text model without its vocabulary head, driven by frame
//  embeddings rather than token ids (`backbone.model.*` in the checkpoint).
//

import MLX
import MLXNN

/// The backbone's embedding table, 40 blocks and final norm.
final class BackboneModel: Module {

    @ModuleInfo(key: "embed_tokens") var embedTokens: Embedding
    @ModuleInfo(key: "layers") var layers: [BackboneLayer]
    @ModuleInfo(key: "norm") var norm: Fp32RMSNorm

    /// - Parameter config: The backbone's shape.
    init(_ config: BackboneConfiguration) {
        _embedTokens.wrappedValue = Embedding(embeddingCount: config.vocabularySize, dimensions: config.hiddenSize)
        _layers.wrappedValue = (0 ..< config.layers).map { BackboneLayer(config, index: $0) }
        _norm.wrappedValue = Fp32RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        super.init()
    }

    /// Fresh caches, one per layer.
    func makeCache() -> [LayerCache] {
        layers.map { $0.makeCache() }
    }

    /// Hidden states `[B, L, D]` for input embeddings `[B, L, D]`.
    func callAsFunction(embeddings: MLXArray, cache: [LayerCache]) -> MLXArray {
        var hidden = embeddings
        for (layer, layerCache) in zip(layers, cache) {
            hidden = layer(hidden, cache: layerCache)
        }
        return norm(hidden)
    }
}
