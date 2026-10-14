//
//  BackboneConfiguration.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// The shape of Drama 3's Qwen3.5-MoE backbone (`text_config`).
struct BackboneConfiguration: Decodable, Sendable {

    /// The rotary settings nested in `rope_parameters`.
    struct Rope: Decodable, Sendable {
        /// RoPE base frequency.
        var ropeTheta: Float
        /// The share of each head that is rotated.
        var partialRotaryFactor: Float

        enum CodingKeys: String, CodingKey {
            case ropeTheta = "rope_theta"
            case partialRotaryFactor = "partial_rotary_factor"
        }
    }

    /// Model width.
    var hiddenSize: Int
    /// Number of blocks.
    var layers: Int
    /// Attention heads in the full-attention layers.
    var attentionHeads: Int
    /// Key/value heads in the full-attention layers.
    var kvHeads: Int
    /// Width of one attention head.
    var headDim: Int
    /// Gated-delta value heads.
    var linearValueHeads: Int
    /// Gated-delta key heads.
    var linearKeyHeads: Int
    /// Gated-delta key head width.
    var linearKeyHeadDim: Int
    /// Gated-delta value head width.
    var linearValueHeadDim: Int
    /// Gated-delta convolution width.
    var linearConvKernel: Int
    /// Norm epsilon.
    var rmsNormEps: Float
    /// Token vocabulary.
    var vocabularySize: Int
    /// Routed experts per layer.
    var experts: Int
    /// Experts chosen per token.
    var expertsPerToken: Int
    /// A routed expert's inner width.
    var moeIntermediateSize: Int
    /// The shared expert's inner width.
    var sharedExpertIntermediateSize: Int
    /// Whether the chosen experts' scores are renormalised.
    var normTopKProb: Bool
    /// Every this-many layers is full attention.
    var fullAttentionInterval: Int
    /// The layer kinds, checked against the every-fourth rule on load.
    var layerTypes: [String]
    /// Rotary settings.
    var rope: Rope

    /// RoPE base frequency.
    var ropeTheta: Float { rope.ropeTheta }
    /// The share of each head that is rotated.
    var partialRotaryFactor: Float { rope.partialRotaryFactor }

    enum CodingKeys: String, CodingKey {
        case hiddenSize = "hidden_size"
        case layers = "num_hidden_layers"
        case attentionHeads = "num_attention_heads"
        case kvHeads = "num_key_value_heads"
        case headDim = "head_dim"
        case linearValueHeads = "linear_num_value_heads"
        case linearKeyHeads = "linear_num_key_heads"
        case linearKeyHeadDim = "linear_key_head_dim"
        case linearValueHeadDim = "linear_value_head_dim"
        case linearConvKernel = "linear_conv_kernel_dim"
        case rmsNormEps = "rms_norm_eps"
        case vocabularySize = "vocab_size"
        case experts = "num_experts"
        case expertsPerToken = "num_experts_per_tok"
        case moeIntermediateSize = "moe_intermediate_size"
        case sharedExpertIntermediateSize = "shared_expert_intermediate_size"
        case normTopKProb = "norm_topk_prob"
        case fullAttentionInterval = "full_attention_interval"
        case layerTypes = "layer_types"
        case rope = "rope_parameters"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hiddenSize = try c.decode(Int.self, forKey: .hiddenSize)
        layers = try c.decode(Int.self, forKey: .layers)
        attentionHeads = try c.decode(Int.self, forKey: .attentionHeads)
        kvHeads = try c.decode(Int.self, forKey: .kvHeads)
        headDim = try c.decode(Int.self, forKey: .headDim)
        linearValueHeads = try c.decode(Int.self, forKey: .linearValueHeads)
        linearKeyHeads = try c.decode(Int.self, forKey: .linearKeyHeads)
        linearKeyHeadDim = try c.decode(Int.self, forKey: .linearKeyHeadDim)
        linearValueHeadDim = try c.decode(Int.self, forKey: .linearValueHeadDim)
        linearConvKernel = try c.decode(Int.self, forKey: .linearConvKernel)
        rmsNormEps = try c.decode(Float.self, forKey: .rmsNormEps)
        vocabularySize = try c.decode(Int.self, forKey: .vocabularySize)
        experts = try c.decode(Int.self, forKey: .experts)
        expertsPerToken = try c.decode(Int.self, forKey: .expertsPerToken)
        moeIntermediateSize = try c.decode(Int.self, forKey: .moeIntermediateSize)
        sharedExpertIntermediateSize = try c.decode(Int.self, forKey: .sharedExpertIntermediateSize)
        normTopKProb = try c.decodeIfPresent(Bool.self, forKey: .normTopKProb) ?? true
        fullAttentionInterval = try c.decodeIfPresent(Int.self, forKey: .fullAttentionInterval) ?? 4
        layerTypes = try c.decode([String].self, forKey: .layerTypes)
        rope = try c.decode(Rope.self, forKey: .rope)
    }
}
