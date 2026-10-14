//
//  CodecStream.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  Incremental decoding for Fish's causal S1 DAC codec: each call decodes only
//  the new frames and carries what the next call needs — each causal
//  convolution's left context, each transposed convolution's overlap tail, and
//  the window-limited transformer's key/value cache. Concatenated, the pieces
//  equal a whole decode.
//
//  mlx-audio-swift's FishS1DAC decodes whole sequences only. Decoding pieces
//  with some earlier frames as context does not work for this codec: its
//  8-layer transformer, windowed at 128 frames, looks back up to 1,024 frames,
//  and measured against a whole decode a 64-frame context scored 6.5 dB SNR
//  and 192 frames 34.6 dB. This ports the streaming step of mlx-audio's
//  fish_s1_dac.py onto FishS1DAC's own modules and weights.
//

import Foundation
import MLX
import MLXAudioCodecs
import MLXNN

/// Decodes a stream of Drama 3 frames piece by piece, exactly.
final class CodecStream {

    let codec: FishS1DAC

    /// What the stream carries between calls. Its arrays are replaced, never
    /// written into, so a copy is a snapshot to go back to.
    struct State {
        var convolutionContext: [ObjectIdentifier: MLXArray] = [:]
        var transposedOverlap: [ObjectIdentifier: MLXArray] = [:]
        var transformerCache: [ObjectIdentifier: [(keys: MLXArray, values: MLXArray)]] = [:]
        var transformerPosition: [ObjectIdentifier: Int] = [:]
    }

    /// The carried state; assign an earlier value to rewind the stream.
    var state = State()

    /// - Parameter codec: The loaded codec; its weights are shared, not copied.
    init(codec: FishS1DAC) {
        self.codec = codec
    }

    /// Audio `[1, 1, frames × 2048]` for the next frames' codes `[1, codebooks, frames]`.
    func step(_ indices: MLXArray) -> MLXArray {
        let quantizer = codec.quantizer
        var z = latents(indices)
        if let transformer = quantizer.postModule as? FishS1WindowLimitedTransformer {
            z = transformerStep(transformer, z)
        } else {
            z = (quantizer.postModule as! UnaryLayer)(z)
        }
        for stage in quantizer.upsample {
            z = transposedStep(stage.conv, z)
            z = convNeXtStep(stage.block, z)
        }
        for layer in codec.decoder.model {
            z = moduleStep(layer, z)
        }
        return z
    }

    // MARK: - Codes to latents

    private func latents(_ indices: MLXArray) -> MLXArray {
        let quantizer = codec.quantizer
        let semantic = clip(indices[0..., 0 ..< 1, 0...], min: 0, max: quantizer.semanticQuantizer.codebookSize - 1)
        let semanticLatents = quantizer.semanticQuantizer.fromCodes(semantic).0
        guard indices.dim(1) > 1 else { return semanticLatents }
        let residual = clip(indices[0..., 1..., 0...], min: 0, max: quantizer.quantizer.codebookSize - 1)
        return semanticLatents + quantizer.quantizer.fromCodes(residual).0
    }

    // MARK: - Convolutions

    private func moduleStep(_ module: Module, _ x: MLXArray) -> MLXArray {
        switch module {
        case let conv as FishS1CausalWNConv1d:
            conv.conv.conv.weight = conv.weight_g * conv.weight_v
                / (weightNorm(conv.weight_v) + 1e-12)
            conv.conv.conv.bias = conv.bias
            return convolutionStep(conv.conv, x)
        case let conv as FishS1CausalWNConvTranspose1d:
            conv.conv.conv.weight = conv.weight_g * conv.weight_v
                / (weightNorm(conv.weight_v) + 1e-12)
            conv.conv.conv.bias = conv.bias
            return transposedStep(conv.conv, x)
        case let conv as FishS1CausalConvNet:
            return convolutionStep(conv, x)
        case let conv as FishS1CausalTransConvNet:
            return transposedStep(conv, x)
        case let unit as FishS1ResidualUnit:
            var y = x
            for layer in unit.block { y = moduleStep(layer, y) }
            return x + y
        case let block as FishS1DecoderBlock:
            var y = x
            for layer in block.block { y = moduleStep(layer, y) }
            return y
        default:
            return (module as! UnaryLayer)(x)
        }
    }

    /// The norm weight normalisation divides by: every axis but the first.
    private func weightNorm(_ v: MLXArray) -> MLXArray {
        sqrt((v * v).sum(axes: Array(1 ..< v.ndim), keepDims: true))
    }

    /// A causal convolution, carrying its left context between calls.
    private func convolutionStep(_ net: FishS1CausalConvNet, _ x: MLXArray) -> MLXArray {
        precondition(net.stride == 1, "streaming needs stride-1 convolutions")
        guard net.padding > 0 else { return net.conv(x) }
        let id = ObjectIdentifier(net)
        let input: MLXArray
        if let context = state.convolutionContext[id] {
            input = concatenated([context, x], axis: -1)
        } else {
            input = padded(x, widths: [IntOrPair(0), IntOrPair(0), IntOrPair((net.padding, 0))])
        }
        state.convolutionContext[id] = input[0..., 0..., (input.dim(-1) - net.padding)...]
        return net.conv(input)
    }

    /// A causal transposed convolution, overlap-adding the tail the causal
    /// trim would drop into the next call.
    private func transposedStep(_ net: FishS1CausalTransConvNet, _ x: MLXArray) -> MLXArray {
        let id = ObjectIdentifier(net)
        var y = net.conv(x)
        let valid = x.dim(-1) * net.stride
        if var carry = state.transposedOverlap[id] {
            // Both halves include the bias; keep it once.
            if let bias = net.conv.bias { carry = carry - bias.expandedDimensions(axis: -1) }
            let n = carry.dim(-1)
            y = concatenated([y[0..., 0..., ..<n] + carry, y[0..., 0..., n...]], axis: -1)
        }
        state.transposedOverlap[id] = y.dim(-1) > valid ? y[0..., 0..., valid...] : nil
        return y[0..., 0..., ..<valid]
    }

    private func convNeXtStep(_ block: FishS1ConvNeXtBlock, _ x: MLXArray) -> MLXArray {
        var y = convolutionStep(block.dwconv, x).transposed(0, 2, 1)
        y = block.pwconv2(block.act(block.pwconv1(block.norm(y))))
        if let gamma = block.gamma { y = gamma * y }
        return x + y.transposed(0, 2, 1)
    }

    // MARK: - Window-limited transformer

    /// Attends new positions to a cache of the last window − 1 positions, using
    /// the same absolute RoPE rows a whole decode uses while the stream fits
    /// the table, and rebasing onto the cached window after that.
    private func transformerStep(_ transformer: FishS1WindowLimitedTransformer, _ input: MLXArray) -> MLXArray {
        let id = ObjectIdentifier(transformer)
        var x = transformer.channelsFirst ? input.transposed(0, 2, 1) : input
        x = (transformer.inputProj as! UnaryLayer)(x)

        let caches = state.transformerCache[id]
        let cached = caches?.first?.keys.dim(1) ?? 0
        let count = x.dim(1)
        let total = cached + count
        let position = state.transformerPosition[id] ?? 0
        let start = min(position - cached, transformer.config.blockSize - total)
        precondition(start >= 0, "a streamed piece is longer than the codec transformer's table")
        state.transformerPosition[id] = position + count

        let rows = MLXArray(Int32(cached) ..< Int32(total)).expandedDimensions(axis: 1)
        let columns = MLXArray(Int32(0) ..< Int32(total)).expandedDimensions(axis: 0)
        var allowed = columns .<= rows
        if let window = transformer.windowSize { allowed = allowed .&& (columns .> rows - Int32(window)) }
        let mask = which(allowed, MLXArray(Float(0)), MLXArray(Float(-1e9))).asType(x.dtype)
            .expandedDimensions(axes: [0, 1])
        let freqs = transformer.freqsCis?[start ..< (start + total)]

        var updated: [(keys: MLXArray, values: MLXArray)] = []
        for (index, layer) in transformer.layers.enumerated() {
            let (attended, cache) = attentionStep(layer.attention, layer.attentionNorm(x), freqs: freqs, mask: mask,
                                                  cache: caches?[index])
            let h = x + layer.attentionLayerScale(attended)
            x = h + layer.ffnLayerScale(layer.feedForward(layer.ffnNorm(h)))
            if let window = transformer.windowSize {
                let keep = window - 1
                let length = cache.keys.dim(1)
                updated.append((cache.keys[0..., max(0, length - keep)...], cache.values[0..., max(0, length - keep)...]))
            } else {
                updated.append(cache)
            }
        }
        state.transformerCache[id] = updated
        x = (transformer.outputProj as! UnaryLayer)(transformer.norm(x))
        return transformer.channelsFirst ? x.transposed(0, 2, 1) : x
    }

    private func attentionStep(_ attention: FishS1Attention, _ x: MLXArray, freqs: MLXArray?, mask: MLXArray,
                               cache: (keys: MLXArray, values: MLXArray)?)
        -> (MLXArray, (keys: MLXArray, values: MLXArray)) {
        let (B, L) = (x.dim(0), x.dim(1))
        let width = attention.nLocalHeads * attention.headDim
        let parts = split(attention.wqkv(x), indices: [width, 2 * width], axis: -1)
        var q = parts[0].reshaped(B, L, attention.nHead, attention.headDim)
        var k = parts[1].reshaped(B, L, attention.nLocalHeads, attention.headDim)
        var v = parts[2].reshaped(B, L, attention.nLocalHeads, attention.headDim)
        if let cache {
            k = concatenated([cache.keys, k], axis: 1)
            v = concatenated([cache.values, v], axis: 1)
        }
        let kept = (keys: k, values: v)
        if attention.posEmbedType == "rope", let freqs {
            q = Self.rotary(q, freqs: freqs[(freqs.dim(0) - L)...])
            k = Self.rotary(k, freqs: freqs)
        }
        q = q.transposed(0, 2, 1, 3)
        k = k.transposed(0, 2, 1, 3)
        v = v.transposed(0, 2, 1, 3)
        if attention.nLocalHeads != attention.nHead {
            let factor = attention.nHead / attention.nLocalHeads
            k = repeated(k, count: factor, axis: 1)
            v = repeated(v, count: factor, axis: 1)
        }
        let y = MLXFast.scaledDotProductAttention(queries: q, keys: k, values: v,
                                                  scale: 1 / Float(attention.headDim).squareRoot(), mask: mask)
            .transposed(0, 2, 1, 3)
            .reshaped(B, L, attention.headDim * attention.nHead)
        return (attention.wo(y), kept)
    }

    /// Interleaved-pair rotary embedding with a `[T, D/2, 2]` cos/sin table.
    static func rotary(_ x: MLXArray, freqs: MLXArray) -> MLXArray {
        let pairs = x.asType(.float32).reshaped(x.shape.dropLast() + [x.dim(-1) / 2, 2])
        let table = freqs.reshaped(1, freqs.dim(0), 1, freqs.dim(1), 2)
        let real = pairs[.ellipsis, 0]
        let imaginary = pairs[.ellipsis, 1]
        let cosine = table[.ellipsis, 0]
        let sine = table[.ellipsis, 1]
        return stacked([real * cosine - imaginary * sine, imaginary * cosine + real * sine], axis: -1)
            .reshaped(x.shape).asType(x.dtype)
    }
}
