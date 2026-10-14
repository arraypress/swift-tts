//
//  TowerFeedForward.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//

import MLX
import MLXNN

/// The tower blocks' SwiGLU MLP.
final class TowerFeedForward: Module, UnaryLayer {

    @ModuleInfo(key: "w1") var w1: Linear
    @ModuleInfo(key: "w2") var w2: Linear
    @ModuleInfo(key: "w3") var w3: Linear

    /// - Parameter config: The tower's shape.
    init(_ config: TowerConfiguration) {
        _w1.wrappedValue = Linear(config.dim, config.intermediateSize, bias: false)
        _w2.wrappedValue = Linear(config.intermediateSize, config.dim, bias: false)
        _w3.wrappedValue = Linear(config.dim, config.intermediateSize, bias: false)
        super.init()
    }

    /// `w2(silu(w1(x)) * w3(x))`.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        w2(silu(w1(x)) * w3(x))
    }
}
