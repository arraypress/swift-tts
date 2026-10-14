//
//  LayerCache.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//

import MLX

/// One backbone layer's cache: attention layers keep keys and values,
/// gated-delta layers a recurrent state.
enum LayerCache {

    /// A full-attention layer.
    case attention(AttentionCache)

    /// A gated-delta layer.
    case recurrent(RecurrentCache)

    /// The arrays to evaluate.
    var state: [MLXArray] {
        switch self {
        case .attention(let cache): cache.state
        case .recurrent(let cache): cache.state
        }
    }

    /// An independent copy.
    func copy() -> LayerCache {
        switch self {
        case .attention(let cache): .attention(cache.copy())
        case .recurrent(let cache): .recurrent(cache.copy())
        }
    }
}
