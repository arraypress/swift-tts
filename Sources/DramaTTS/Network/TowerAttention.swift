//
//  TowerAttention.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  Gated grouped-query attention for the audio tower. `wqkv` rows are
//  [all Q | all gates | K | V]; RoPE is interleaved over a quarter of each
//  head, rotated in float32 as the reference does.
//

import MLX
import MLXNN

/// The tower blocks' attention.
final class TowerAttention: Module {

    let heads: Int
    let kvHeads: Int
    let headDim: Int
    let queryWidth: Int
    let kvWidth: Int
    let rotaryDims: Int
    let ropeBase: Float

    @ModuleInfo(key: "wqkv") var wqkv: Linear
    @ModuleInfo(key: "wo") var wo: Linear
    @ModuleInfo(key: "q_norm") var qNorm: Fp32RMSNorm
    @ModuleInfo(key: "k_norm") var kNorm: Fp32RMSNorm

    /// - Parameter config: The tower's shape.
    init(_ config: TowerConfiguration) {
        heads = config.heads
        kvHeads = config.kvHeads
        headDim = config.headDim
        queryWidth = heads * headDim
        kvWidth = kvHeads * headDim
        rotaryDims = Int(Float(headDim) * config.rotaryPercent)
        ropeBase = config.ropeBase
        _wqkv.wrappedValue = Linear(config.dim, 2 * queryWidth + 2 * kvWidth, bias: false)
        _wo.wrappedValue = Linear(queryWidth, config.dim, bias: false)
        _qNorm.wrappedValue = Fp32RMSNorm(dimensions: headDim, eps: config.normEps)
        _kNorm.wrappedValue = Fp32RMSNorm(dimensions: headDim, eps: config.normEps)
        super.init()
    }

    private func rope(_ x: MLXArray, offset: Int) -> MLXArray {
        MLXFast.RoPE(x.asType(.float32), dimensions: rotaryDims, traditional: true, base: ropeBase,
                     scale: 1, offset: offset).asType(x.dtype)
    }

    /// Attends over `[B, T, D]`, appending to the cache.
    func callAsFunction(_ x: MLXArray, cache: AttentionCache) -> MLXArray {
        let (B, T) = (x.dim(0), x.dim(1))
        let parts = split(wqkv(x), indices: [queryWidth, 2 * queryWidth, 2 * queryWidth + kvWidth], axis: -1)
        let queries = qNorm(parts[0].reshaped(B, T, heads, headDim))
        let gate = parts[1]
        let keys = kNorm(parts[2].reshaped(B, T, kvHeads, headDim))
        let values = parts[3].reshaped(B, T, kvHeads, headDim).transposed(0, 2, 1, 3)
        let q = rope(queries.transposed(0, 2, 1, 3), offset: cache.offset)
        let k = rope(keys.transposed(0, 2, 1, 3), offset: cache.offset)
        let (allKeys, allValues) = cache.update(keys: k, values: values)
        let out = MLXFast.scaledDotProductAttention(
            queries: q, keys: allKeys, values: allValues, scale: 1 / Float(headDim).squareRoot(),
            mask: T > 1 ? .causal : .none)
            .transposed(0, 2, 1, 3)
            .reshaped(B, T, queryWidth)
        return wo(out * sigmoid(gate))
    }
}
