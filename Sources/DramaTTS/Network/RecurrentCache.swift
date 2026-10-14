//
//  RecurrentCache.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//

import MLX

/// The state a gated-delta layer carries between calls: the convolution's last
/// inputs and the recurrent state.
final class RecurrentCache {

    /// `[B, kernel - 1, convDim]`.
    var convolution: MLXArray?

    /// `[B, Hv, Dv, Dk]`, float32.
    var recurrent: MLXArray?

    /// An empty cache.
    init() {}

    /// The arrays to evaluate.
    var state: [MLXArray] { [convolution, recurrent].compactMap { $0 } }

    /// A copy. Both arrays are replaced, never written into, so sharing is safe.
    func copy() -> RecurrentCache {
        let clone = RecurrentCache()
        clone.convolution = convolution
        clone.recurrent = recurrent
        return clone
    }
}
