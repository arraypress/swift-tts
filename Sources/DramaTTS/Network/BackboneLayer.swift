//
//  BackboneLayer.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//

import MLX
import MLXNN

/// One backbone block: gated-delta or full attention, then the experts.
final class BackboneLayer: Module {

    /// Whether this is a gated-delta (linear-attention) layer.
    let isLinear: Bool

    @ModuleInfo(key: "self_attn") var selfAttention: BackboneAttention?
    @ModuleInfo(key: "linear_attn") var linearAttention: GatedDeltaNet?
    @ModuleInfo(key: "input_layernorm") var inputNorm: Fp32RMSNorm
    @ModuleInfo(key: "post_attention_layernorm") var postAttentionNorm: Fp32RMSNorm
    @ModuleInfo(key: "mlp") var mlp: SparseMoE

    /// - Parameters:
    ///   - config: The backbone's shape.
    ///   - index: The layer's position; every fourth is full attention.
    init(_ config: BackboneConfiguration, index: Int) {
        isLinear = (index + 1) % config.fullAttentionInterval != 0
        if isLinear {
            _linearAttention.wrappedValue = GatedDeltaNet(config)
        } else {
            _selfAttention.wrappedValue = BackboneAttention(config)
        }
        _inputNorm.wrappedValue = Fp32RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        _postAttentionNorm.wrappedValue = Fp32RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        _mlp.wrappedValue = SparseMoE(config)
        super.init()
    }

    /// A fresh cache of the right kind.
    func makeCache() -> LayerCache {
        isLinear ? .recurrent(RecurrentCache()) : .attention(AttentionCache())
    }

    /// Runs `[B, L, D]` through the block.
    func callAsFunction(_ x: MLXArray, cache: LayerCache) -> MLXArray {
        let normed = inputNorm(x)
        let mixed: MLXArray
        switch cache {
        case .recurrent(let state): mixed = linearAttention!(normed, cache: state)
        case .attention(let state): mixed = selfAttention!(normed, cache: state)
        }
        let h = x + mixed
        return h + mlp(postAttentionNorm(h))
    }
}
