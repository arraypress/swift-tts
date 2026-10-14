//
//  DramaNetwork.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  Everything in Drama 3's model shards: the backbone, the semantic head (only
//  the semantic band and EOS can be sampled, so it holds those rows instead of
//  the whole vocabulary) and the audio tower. The codec loads separately.
//

import MLX
import MLXNN

/// The backbone, semantic head and tower, keyed as the checkpoint keys them.
final class DramaNetwork: Module {

    @ModuleInfo(key: "backbone") var backbone: Backbone
    @ModuleInfo(key: "semantic_head") var semanticHead: Linear
    @ModuleInfo(key: "tower") var tower: Tower

    /// - Parameter config: The model's configuration.
    init(_ config: DramaConfiguration) {
        _backbone.wrappedValue = Backbone(config.text)
        let band = config.semanticEndTokenID - config.semanticStartTokenID + 1
        _semanticHead.wrappedValue = Linear(config.text.hiddenSize, band + 1, bias: false)
        _tower.wrappedValue = Tower(config.tower, semanticBegin: config.semanticStartTokenID,
                                    semanticEnd: config.semanticEndTokenID)
        super.init()
    }

    /// Backbone input for frame rows `[B, T, 11]`.
    func embed(_ frames: MLXArray) -> MLXArray {
        tower.embedBackbone(frames, text: backbone.model.embedTokens(frames[.ellipsis, 0]))
    }
}
