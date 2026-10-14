//
//  Fp32RMSNorm.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  Drama 3's norms are zero-centred; the checkpoint stores them already shifted
//  to 1 + w, in float32, because bfloat16 only resolves steps of 1/128 near 1.
//  They are computed in float32 and cast back, as the reference does.
//

import MLX
import MLXNN

/// RMSNorm with a float32 gamma, computed in float32 and cast back.
final class Fp32RMSNorm: Module, UnaryLayer {

    /// The gamma, already `1 + w`.
    var weight: MLXArray

    /// The variance epsilon.
    let eps: Float

    /// - Parameters:
    ///   - dimensions: The normalised width.
    ///   - eps: The variance epsilon.
    init(dimensions: Int, eps: Float) {
        self.weight = MLXArray.ones([dimensions], dtype: .float32)
        self.eps = eps
        super.init()
    }

    /// Normalises the last axis.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        MLXFast.rmsNorm(x.asType(.float32), weight: weight, eps: eps).asType(x.dtype)
    }
}
