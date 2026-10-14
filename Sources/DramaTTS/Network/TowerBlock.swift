//
//  TowerBlock.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//

import MLX
import MLXNN

/// A pre-norm transformer block of the tower.
final class TowerBlock: Module {

    @ModuleInfo(key: "attention") var attention: TowerAttention
    @ModuleInfo(key: "attention_norm") var attentionNorm: Fp32RMSNorm
    @ModuleInfo(key: "ffn_norm") var ffnNorm: Fp32RMSNorm
    @ModuleInfo(key: "feed_forward") var feedForward: TowerFeedForward

    /// - Parameter config: The tower's shape.
    init(_ config: TowerConfiguration) {
        _attention.wrappedValue = TowerAttention(config)
        _attentionNorm.wrappedValue = Fp32RMSNorm(dimensions: config.dim, eps: config.normEps)
        _ffnNorm.wrappedValue = Fp32RMSNorm(dimensions: config.dim, eps: config.normEps)
        _feedForward.wrappedValue = TowerFeedForward(config)
        super.init()
    }

    /// Runs `[B, T, D]` through the block.
    func callAsFunction(_ x: MLXArray, cache: AttentionCache) -> MLXArray {
        let h = x + attention(attentionNorm(x), cache: cache)
        return h + feedForward(ffnNorm(h))
    }
}
