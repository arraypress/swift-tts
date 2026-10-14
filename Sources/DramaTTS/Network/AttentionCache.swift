//
//  AttentionCache.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  Keys and values grow in steps of 256 positions and are written into place,
//  as mlx-lm's KVCache does. ``copy()`` slices to the filled length, so a
//  snapshot never shares storage with the cache it came from.
//

import MLX

/// A key/value cache for one attention layer.
final class AttentionCache {

    /// Positions are allocated this many at a time.
    static let step = 256

    /// Filled positions.
    private(set) var offset = 0

    private var keys: MLXArray?
    private var values: MLXArray?

    /// An empty cache.
    init() {}

    /// Appends `[B, H, T, D]` keys and values; returns everything so far.
    func update(keys newKeys: MLXArray, values newValues: MLXArray) -> (MLXArray, MLXArray) {
        let previous = offset
        let count = newKeys.dim(2)
        if keys == nil || previous + count > keys!.dim(2) {
            let (B, H, Dk, Dv) = (newKeys.dim(0), newKeys.dim(1), newKeys.dim(3), newValues.dim(3))
            let grow = ((count + Self.step - 1) / Self.step) * Self.step
            let moreKeys = MLXArray.zeros([B, H, grow, Dk], dtype: newKeys.dtype)
            let moreValues = MLXArray.zeros([B, H, grow, Dv], dtype: newValues.dtype)
            if let keys, let values {
                let trimmedKeys = previous % Self.step != 0 ? keys[.ellipsis, ..<previous, 0...] : keys
                let trimmedValues = previous % Self.step != 0 ? values[.ellipsis, ..<previous, 0...] : values
                self.keys = concatenated([trimmedKeys, moreKeys], axis: 2)
                self.values = concatenated([trimmedValues, moreValues], axis: 2)
            } else {
                self.keys = moreKeys
                self.values = moreValues
            }
        }
        offset += count
        keys![.ellipsis, previous ..< offset, 0...] = newKeys
        values![.ellipsis, previous ..< offset, 0...] = newValues
        return (keys![.ellipsis, ..<offset, 0...], values![.ellipsis, ..<offset, 0...])
    }

    /// The arrays to evaluate.
    var state: [MLXArray] { [keys, values].compactMap { $0 } }

    /// An independent copy of the filled positions.
    func copy() -> AttentionCache {
        let clone = AttentionCache()
        if let keys, let values {
            clone.keys = keys[.ellipsis, ..<offset, 0...]
            clone.values = values[.ellipsis, ..<offset, 0...]
        }
        clone.offset = offset
        return clone
    }
}
