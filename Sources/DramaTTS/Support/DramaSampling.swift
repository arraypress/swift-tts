//
//  DramaSampling.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  The reference recipe's sampler. Temperature applies before top-p; the
//  cumulative probability runs over the full vocabulary; the token that crosses
//  top-p is dropped unless it ranks first. Only the top-k candidates are sorted.
//

import MLX

/// Top-k / top-p sampling as Drama 3's training recipe samples.
enum DramaSampling {

    /// Below this, temperature is treated as this (greedy in effect).
    static let minimumTemperature: Float = 1e-5

    /// Repetition-aware sampling: a semantic main token that repeats one of the
    /// last `window` main tokens is replaced by a second draw at these settings.
    static let repetitionWindow = 16
    static let repetitionTemperature: Float = 1.0
    static let repetitionTopK = 30
    static let repetitionTopP: Float = 0.95

    /// One id per row of logits `[B, V]`.
    static func sample(_ logits: MLXArray, temperature: Float, topK: Int, topP: Float) -> MLXArray {
        var x = logits.asType(.float32) / max(temperature, minimumTemperature)
        // At low temperature the logits share a huge offset that would swamp
        // the log-sum-exp in float32 and push every probability to 1.
        x = x - x.max(axis: -1, keepDims: true)
        let k = min(topK, x.dim(-1))
        var ids = argPartition(-x, kth: k - 1, axis: -1)[.ellipsis, ..<k]
        var values = takeAlong(x, ids, axis: -1)
        let order = argSort(-values, axis: -1)
        values = takeAlong(values, order, axis: -1)
        ids = takeAlong(ids, order, axis: -1)
        let probabilities = exp(values - logSumExp(x, axis: -1, keepDims: true))
        let dropped = (cumsum(probabilities, axis: -1) .> topP) .&& (MLXArray(Int32(0) ..< Int32(k)) .> 0)
        let choice = categorical(which(dropped, MLXArray(-Float.infinity), values))
        return takeAlong(ids, choice.expandedDimensions(axis: -1), axis: -1)[.ellipsis, 0]
    }
}
