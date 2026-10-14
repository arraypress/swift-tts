//
//  SparseMoE.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  256 routed experts, 8 active per token, plus a gated shared expert. The
//  routed experts are mlx-swift-lm's SwitchGLU (4-bit in this checkpoint).
//

import MLX
import MLXLMCommon
import MLXNN

/// The mixture-of-experts MLP of every backbone layer.
final class SparseMoE: Module, UnaryLayer {

    let topK: Int
    let normTopKProb: Bool

    @ModuleInfo(key: "gate") var gate: Linear
    @ModuleInfo(key: "switch_mlp") var switchMLP: SwitchGLU
    @ModuleInfo(key: "shared_expert") var sharedExpert: SharedExpert
    @ModuleInfo(key: "shared_expert_gate") var sharedExpertGate: Linear

    /// - Parameter config: The backbone's shape.
    init(_ config: BackboneConfiguration) {
        topK = config.expertsPerToken
        normTopKProb = config.normTopKProb
        _gate.wrappedValue = Linear(config.hiddenSize, config.experts, bias: false)
        _switchMLP.wrappedValue = SwitchGLU(inputDims: config.hiddenSize, hiddenDims: config.moeIntermediateSize,
                                            numExperts: config.experts)
        _sharedExpert.wrappedValue = SharedExpert(dimensions: config.hiddenSize,
                                                  hidden: config.sharedExpertIntermediateSize)
        _sharedExpertGate.wrappedValue = Linear(config.hiddenSize, 1, bias: false)
        super.init()
    }

    /// Routes each token to its experts and mixes in the shared one.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let gates = softmax(gate(x), axis: -1, precise: true)
        let kth = gates.dim(-1) - topK
        let indices = argPartition(gates, kth: kth, axis: -1)[.ellipsis, kth...]
        var scores = takeAlong(gates, indices, axis: -1)
        if normTopKProb {
            scores = scores / scores.sum(axis: -1, keepDims: true)
        }
        let routed = (switchMLP(x, indices) * scores.expandedDimensions(axis: -1)).sum(axis: -2)
        return routed + sigmoid(sharedExpertGate(x)) * sharedExpert(x)
    }
}
