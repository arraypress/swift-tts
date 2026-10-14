//
//  BackboneAttention.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  The backbone's full-attention layer (every fourth): grouped-query attention
//  with an output gate folded into q_proj, per-head q/k norms, and partial RoPE
//  (a quarter of each head). Ported from mlx-lm's Qwen3NextAttention.
//

import MLX
import MLXNN

/// Gated grouped-query attention.
final class BackboneAttention: Module {

    let heads: Int
    let kvHeads: Int
    let headDim: Int
    let ropeDims: Int
    let ropeBase: Float
    let scale: Float

    @ModuleInfo(key: "q_proj") var qProj: Linear
    @ModuleInfo(key: "k_proj") var kProj: Linear
    @ModuleInfo(key: "v_proj") var vProj: Linear
    @ModuleInfo(key: "o_proj") var oProj: Linear
    @ModuleInfo(key: "q_norm") var qNorm: Fp32RMSNorm
    @ModuleInfo(key: "k_norm") var kNorm: Fp32RMSNorm

    /// - Parameter config: The backbone's shape.
    init(_ config: BackboneConfiguration) {
        heads = config.attentionHeads
        kvHeads = config.kvHeads
        headDim = config.headDim
        ropeDims = Int(Float(config.headDim) * config.partialRotaryFactor)
        ropeBase = config.ropeTheta
        scale = 1 / Float(config.headDim).squareRoot()
        _qProj.wrappedValue = Linear(config.hiddenSize, heads * headDim * 2, bias: false)
        _kProj.wrappedValue = Linear(config.hiddenSize, kvHeads * headDim, bias: false)
        _vProj.wrappedValue = Linear(config.hiddenSize, kvHeads * headDim, bias: false)
        _oProj.wrappedValue = Linear(heads * headDim, config.hiddenSize, bias: false)
        _qNorm.wrappedValue = Fp32RMSNorm(dimensions: headDim, eps: config.rmsNormEps)
        _kNorm.wrappedValue = Fp32RMSNorm(dimensions: headDim, eps: config.rmsNormEps)
        super.init()
    }

    /// Attends over `[B, L, D]`, appending to the cache.
    func callAsFunction(_ x: MLXArray, cache: AttentionCache) -> MLXArray {
        let (B, L) = (x.dim(0), x.dim(1))
        let halves = qProj(x).reshaped(B, L, heads, -1).split(parts: 2, axis: -1)
        let gate = halves[1].reshaped(B, L, -1)
        var queries = qNorm(halves[0]).transposed(0, 2, 1, 3)
        var keys = kNorm(kProj(x).reshaped(B, L, kvHeads, -1)).transposed(0, 2, 1, 3)
        var values = vProj(x).reshaped(B, L, kvHeads, -1).transposed(0, 2, 1, 3)
        queries = MLXFast.RoPE(queries, dimensions: ropeDims, traditional: false, base: ropeBase,
                               scale: 1, offset: cache.offset)
        keys = MLXFast.RoPE(keys, dimensions: ropeDims, traditional: false, base: ropeBase,
                            scale: 1, offset: cache.offset)
        (keys, values) = cache.update(keys: keys, values: values)
        let output = MLXFast.scaledDotProductAttention(
            queries: queries, keys: keys, values: values, scale: scale, mask: L > 1 ? .causal : .none)
            .transposed(0, 2, 1, 3)
            .reshaped(B, L, -1)
        return oProj(output * sigmoid(gate))
    }
}
