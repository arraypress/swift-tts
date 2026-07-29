//
//  SupertonicAssets.swift
//  SupertonicTTS
//
//  The JSON that ships beside the ONNX graphs: model geometry and voice styles.
//

import Foundation
import OnnxRuntimeBindings

/// Model geometry, from `onnx/tts.json`.
///
/// Read rather than hardcoded — the latent dimensions and chunk size decide the shape of every
/// tensor in the denoise loop, and a future revision that changes them would otherwise produce
/// silent shape mismatches deep in the pipeline.
struct Config: Decodable {

    struct AE: Decodable {
        let sampleRate: Int
        let baseChunkSize: Int

        enum CodingKeys: String, CodingKey {
            case sampleRate = "sample_rate"
            case baseChunkSize = "base_chunk_size"
        }
    }

    struct TTL: Decodable {
        let latentDim: Int
        let chunkCompressFactor: Int

        enum CodingKeys: String, CodingKey {
            case latentDim = "latent_dim"
            case chunkCompressFactor = "chunk_compress_factor"
        }
    }

    let ae: AE
    let ttl: TTL

    init(contentsOf url: URL) throws {
        self = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
    }
}

// MARK: - Voice Style

/// One speaker, from `voice_styles/<id>.json`.
///
/// Two conditioning tensors rather than one: `style_ttl` (50×256) steers the text encoder and
/// the denoiser, `style_dp` (8×16) steers duration prediction — which is why a voice changes
/// pacing as well as timbre.
struct VoiceStyle {

    private struct File: Decodable {
        struct Component: Decodable {
            let data: [[[Float]]]
            let dims: [Int]
        }
        let style_ttl: Component
        let style_dp: Component
    }

    private let ttl: (values: [Float], shape: [Int])
    private let dp: (values: [Float], shape: [Int])

    init(contentsOf url: URL) throws {
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        ttl = (file.style_ttl.data.flatMap { $0.flatMap { $0 } }, file.style_ttl.dims)
        dp = (file.style_dp.data.flatMap { $0.flatMap { $0 } }, file.style_dp.dims)
    }

    func ttlValue() throws -> ORTValue { try ORTValue(float: ttl.values, shape: ttl.shape) }

    func dpValue() throws -> ORTValue { try ORTValue(float: dp.values, shape: dp.shape) }
}
