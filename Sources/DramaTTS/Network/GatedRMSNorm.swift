//
//  GatedRMSNorm.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//

import MLX
import MLXNN

/// The gated-delta output norm: RMSNorm, then `silu(gate) * x` in float32.
final class GatedRMSNorm: Module {

    /// The gamma (not zero-centred; stored as is).
    var weight: MLXArray

    /// The variance epsilon.
    let eps: Float

    /// - Parameters:
    ///   - dimensions: The normalised width (one value head).
    ///   - eps: The variance epsilon.
    init(dimensions: Int, eps: Float) {
        self.weight = MLXArray.ones([dimensions])
        self.eps = eps
        super.init()
    }

    /// Normalises `x` and gates it by `gate`.
    func callAsFunction(_ x: MLXArray, gate: MLXArray) -> MLXArray {
        let normed = MLXFast.rmsNorm(x, weight: weight, eps: eps)
        return (silu(gate.asType(.float32)) * normed.asType(.float32)).asType(x.dtype)
    }
}
