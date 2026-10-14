//
//  TowerConfiguration.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// The shape of the audio tower (`audio_decoder_config`).
struct TowerConfiguration: Decodable, Sendable {

    /// Model width.
    var dim: Int
    /// Attention heads.
    var heads: Int
    /// Key/value heads.
    var kvHeads: Int
    /// Width of one head.
    var headDim: Int
    /// MLP inner width.
    var intermediateSize: Int
    /// Codes per codebook.
    var vocabularySize: Int
    /// Codebooks per frame.
    var codebooks: Int
    /// Shared enrichment layers before the residual ones.
    var sharedEnrichmentLayers: Int
    /// Residual codebooks mixed into the backbone input.
    var backboneCodebooks: Int
    /// Norm epsilon.
    var normEps: Float
    /// RoPE base frequency.
    var ropeBase: Float
    /// The share of each head that is rotated.
    var rotaryPercent: Float

    enum CodingKeys: String, CodingKey {
        case dim
        case heads = "n_head"
        case kvHeads = "n_local_heads"
        case headDim = "head_dim"
        case intermediateSize = "intermediate_size"
        case vocabularySize = "vocab_size"
        case codebooks = "num_codebooks"
        case sharedEnrichmentLayers = "shared_enrichment_layers"
        case backboneCodebooks = "vq_backbone_codebooks"
        case normEps = "norm_eps"
        case ropeBase = "rope_base"
        case rotaryPercent = "rotary_percent"
    }
}
