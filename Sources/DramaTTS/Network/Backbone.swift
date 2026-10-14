//
//  Backbone.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//

import MLX
import MLXNN

/// `backbone.*` in the checkpoint: the text model, whose vocabulary head
/// Drama 3 replaces with ``DramaNetwork/semanticHead``.
final class Backbone: Module {

    @ModuleInfo(key: "model") var model: BackboneModel

    /// - Parameter config: The backbone's shape.
    init(_ config: BackboneConfiguration) {
        _model.wrappedValue = BackboneModel(config)
        super.init()
    }
}
