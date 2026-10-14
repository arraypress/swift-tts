//
//  TowerLayer.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  Mixes a code embedding (zero on text rows) into the hidden state, then runs
//  one block. Enrichment layers name their table `semantic_embedding`,
//  residual layers `codebook_embedding`.
//

import MLX
import MLXNN

/// One tower layer: embed a code, mix it with the hidden state, run a block.
final class TowerLayer: Module {

    let vocabularySize: Int

    @ModuleInfo(key: "semantic_embedding") var semanticEmbedding: Embedding?
    @ModuleInfo(key: "codebook_embedding") var codebookEmbedding: Embedding?
    @ModuleInfo(key: "enorm") var enorm: Fp32RMSNorm
    @ModuleInfo(key: "hnorm") var hnorm: Fp32RMSNorm
    @ModuleInfo(key: "eh_proj") var ehProj: Linear
    @ModuleInfo(key: "transformer_layer") var transformerLayer: TowerBlock
    @ModuleInfo(key: "final_layernorm") var finalNorm: Fp32RMSNorm

    /// - Parameters:
    ///   - config: The tower's shape.
    ///   - enrichment: Whether this is one of the shared enrichment layers.
    init(_ config: TowerConfiguration, enrichment: Bool) {
        vocabularySize = config.vocabularySize
        let table = Embedding(embeddingCount: config.vocabularySize, dimensions: config.dim)
        if enrichment {
            _semanticEmbedding.wrappedValue = table
        } else {
            _codebookEmbedding.wrappedValue = table
        }
        _enorm.wrappedValue = Fp32RMSNorm(dimensions: config.dim, eps: config.normEps)
        _hnorm.wrappedValue = Fp32RMSNorm(dimensions: config.dim, eps: config.normEps)
        _ehProj.wrappedValue = Linear(2 * config.dim, config.dim, bias: false)
        _transformerLayer.wrappedValue = TowerBlock(config)
        _finalNorm.wrappedValue = Fp32RMSNorm(dimensions: config.dim, eps: config.normEps)
        super.init()
    }

    /// - Parameters:
    ///   - hidden: `[B, T, D]`.
    ///   - codes: `[B, T]` codes to embed.
    ///   - semantic: `[B, T]` whether each row is an audio row.
    ///   - cache: This layer's cache.
    ///   - extra: An embedding added before mixing (the first enrichment layer's).
    func callAsFunction(_ hidden: MLXArray, codes: MLXArray, semantic: MLXArray, cache: AttentionCache,
                        extra: MLXArray? = nil) -> MLXArray {
        let table = (semanticEmbedding ?? codebookEmbedding)!
        let embedded = table(clip(codes, min: 0, max: vocabularySize - 1))
        var e = which(semantic.expandedDimensions(axis: -1), embedded, zeros(like: embedded))
        if let extra { e = e + extra }
        let mixed = ehProj(concatenated([enorm(e), hnorm(hidden)], axis: -1))
        return finalNorm(transformerLayer(mixed, cache: cache)).asType(mixed.dtype)
    }
}
