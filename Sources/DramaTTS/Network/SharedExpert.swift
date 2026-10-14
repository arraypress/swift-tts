//
//  SharedExpert.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//

import MLX
import MLXNN

/// The always-on expert beside the routed ones: a SwiGLU MLP.
final class SharedExpert: Module, UnaryLayer {

    @ModuleInfo(key: "gate_proj") var gateProj: Linear
    @ModuleInfo(key: "up_proj") var upProj: Linear
    @ModuleInfo(key: "down_proj") var downProj: Linear

    /// - Parameters:
    ///   - dimensions: The model width.
    ///   - hidden: The expert's inner width.
    init(dimensions: Int, hidden: Int) {
        _gateProj.wrappedValue = Linear(dimensions, hidden, bias: false)
        _upProj.wrappedValue = Linear(dimensions, hidden, bias: false)
        _downProj.wrappedValue = Linear(hidden, dimensions, bias: false)
        super.init()
    }

    /// `down(silu(gate(x)) * up(x))`.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        downProj(silu(gateProj(x)) * upProj(x))
    }
}
