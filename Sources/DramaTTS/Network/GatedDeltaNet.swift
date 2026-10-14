//
//  GatedDeltaNet.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  The backbone's linear-attention layer (three of every four): a causal
//  depthwise convolution over q/k/v, then the gated delta rule, run by
//  mlx-swift-lm's Metal kernel. Ported from mlx-lm's qwen3_5 GatedDeltaNet.
//

import MLX
import MLXLMCommon
import MLXNN

/// Gated DeltaNet linear attention.
final class GatedDeltaNet: Module {

    let numVHeads: Int
    let numKHeads: Int
    let headKDim: Int
    let headVDim: Int
    let keyDim: Int
    let valueDim: Int
    let convKernel: Int
    let convDim: Int

    @ModuleInfo(key: "conv1d") var conv1d: Conv1d
    @ModuleInfo(key: "in_proj_qkv") var inProjQKV: Linear
    @ModuleInfo(key: "in_proj_z") var inProjZ: Linear
    @ModuleInfo(key: "in_proj_b") var inProjB: Linear
    @ModuleInfo(key: "in_proj_a") var inProjA: Linear
    @ParameterInfo(key: "dt_bias") var dtBias: MLXArray
    @ParameterInfo(key: "A_log") var aLog: MLXArray
    @ModuleInfo(key: "norm") var norm: GatedRMSNorm
    @ModuleInfo(key: "out_proj") var outProj: Linear

    /// - Parameter config: The backbone's shape.
    init(_ config: BackboneConfiguration) {
        numVHeads = config.linearValueHeads
        numKHeads = config.linearKeyHeads
        headKDim = config.linearKeyHeadDim
        headVDim = config.linearValueHeadDim
        keyDim = headKDim * numKHeads
        valueDim = headVDim * numVHeads
        convKernel = config.linearConvKernel
        convDim = keyDim * 2 + valueDim
        _conv1d.wrappedValue = Conv1d(inputChannels: convDim, outputChannels: convDim, kernelSize: convKernel,
                                      groups: convDim, bias: false)
        _inProjQKV.wrappedValue = Linear(config.hiddenSize, keyDim * 2 + valueDim, bias: false)
        _inProjZ.wrappedValue = Linear(config.hiddenSize, valueDim, bias: false)
        _inProjB.wrappedValue = Linear(config.hiddenSize, numVHeads, bias: false)
        _inProjA.wrappedValue = Linear(config.hiddenSize, numVHeads, bias: false)
        _dtBias.wrappedValue = MLXArray.ones([numVHeads])
        _aLog.wrappedValue = MLXArray.zeros([numVHeads])
        _norm.wrappedValue = GatedRMSNorm(dimensions: headVDim, eps: config.rmsNormEps)
        _outProj.wrappedValue = Linear(valueDim, config.hiddenSize, bias: false)
        super.init()
    }

    /// Runs `[B, S, D]` through the layer, carrying state in the cache.
    func callAsFunction(_ inputs: MLXArray, cache: RecurrentCache) -> MLXArray {
        let (B, S) = (inputs.dim(0), inputs.dim(1))
        let qkv = inProjQKV(inputs)
        let z = inProjZ(inputs).reshaped(B, S, numVHeads, headVDim)
        let b = inProjB(inputs)
        let a = inProjA(inputs)

        let convState = cache.convolution
            ?? MLXArray.zeros([B, convKernel - 1, convDim], dtype: inputs.dtype)
        let convInput = concatenated([convState, qkv], axis: 1)
        cache.convolution = contiguous(convInput[0..., (-(convKernel - 1))..., 0...])
        let convOut = silu(conv1d(convInput))

        let parts = split(convOut, indices: [keyDim, 2 * keyDim], axis: -1)
        let q = parts[0].reshaped(B, S, numKHeads, headKDim)
        let k = parts[1].reshaped(B, S, numKHeads, headKDim)
        let v = parts[2].reshaped(B, S, numVHeads, headVDim)

        let invScale = 1 / Float(headKDim).squareRoot()
        let qNormed = MLXArray(invScale * invScale).asType(q.dtype)
            * MLXFast.rmsNorm(q, weight: MLXArray.mlxNone, eps: 1e-6)
        let kNormed = MLXArray(invScale).asType(k.dtype)
            * MLXFast.rmsNorm(k, weight: MLXArray.mlxNone, eps: 1e-6)

        let (out, state) = gatedDeltaUpdate(q: qNormed, k: kNormed, v: v, a: a, b: b, aLog: aLog, dtBias: dtBias,
                                            state: cache.recurrent, mask: nil)
        cache.recurrent = state
        return outProj(norm(out, gate: z).reshaped(B, S, -1))
    }
}
