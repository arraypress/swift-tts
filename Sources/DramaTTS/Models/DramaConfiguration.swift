//
//  DramaConfiguration.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Drama 3's `config.json`: the backbone, the tower and the special ids.
struct DramaConfiguration: Decodable, Sendable {

    /// The backbone's shape.
    var text: BackboneConfiguration
    /// The tower's shape.
    var tower: TowerConfiguration
    /// `<|semantic:0|>`.
    var semanticStartTokenID: Int
    /// The last semantic token.
    var semanticEndTokenID: Int
    /// `<|im_end|>`, which ends a frame sequence.
    var eosTokenID: Int
    /// The prompt template the weights were trained on.
    var speechTemplateVersion: String
    /// The checkpoint's quantisation: a default and per-layer overrides.
    var quantization: QuantizationTable?

    enum CodingKeys: String, CodingKey {
        case text = "text_config"
        case tower = "audio_decoder_config"
        case semanticStartTokenID = "semantic_start_token_id"
        case semanticEndTokenID = "semantic_end_token_id"
        case eosTokenID = "eos_token_id"
        case speechTemplateVersion = "speech_template_version"
        case quantization
    }
}
