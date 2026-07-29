//
//  SupertonicPipeline.swift
//  SupertonicTTS
//
//  The four-stage inference: duration → text embedding → flow-matching denoise
//  loop → vocoder. Ported from Supertone's reference Swift implementation.
//

import Foundation
import OnnxRuntimeBindings

/// Runs one synthesis through the four Supertonic graphs.
struct SupertonicPipeline {

    let sessions: Sessions
    let config: Config
    let indexer: [Int64]
    let steps: Int

    /// Duration is predicted for a neutral pace; the reference divides by this to land on
    /// natural-sounding speech. Kept as the reference's own constant rather than folded into
    /// the caller's rate, so `rate: 1.0` means "as the model intends".
    private static let referenceSpeed: Float = 1.05

    /// Text in, mono float samples out at the model's sample rate.
    func synthesize(text: String, style: VoiceStyle, speed: Float) throws -> [Float] {
        let ids = tokenize(text)
        guard !ids.isEmpty else { return [] }

        let textIds = try ORTValue(int64: ids, shape: [1, ids.count])
        let textMask = try ORTValue(float: [Float](repeating: 1, count: ids.count), shape: [1, 1, ids.count])

        // 1 — how long the utterance should be
        let durationOut = try sessions.durationPredictor.run(
            withInputs: ["text_ids": textIds, "style_dp": try style.dpValue(), "text_mask": textMask],
            outputNames: ["duration"],
            runOptions: nil
        )
        let rate = max(speed, 0.1) * Self.referenceSpeed
        let duration = (try durationOut["duration"]!.floats()).map { $0 / rate }
        guard let seconds = duration.max(), seconds > 0 else { return [] }

        // 2 — encode the text once; the denoise loop reuses it every step
        let encoded = try sessions.textEncoder.run(
            withInputs: ["text_ids": textIds, "style_ttl": try style.ttlValue(), "text_mask": textMask],
            outputNames: ["text_emb"],
            runOptions: nil
        )
        let textEmb = encoded["text_emb"]!

        // 3 — flow matching, from noise to a speech latent
        let chunk = config.ae.baseChunkSize * config.ttl.chunkCompressFactor
        let latentLength = (Int(seconds * Float(config.ae.sampleRate)) + chunk - 1) / chunk
        let latentDim = config.ttl.latentDim * config.ttl.chunkCompressFactor
        guard latentLength > 0 else { return [] }

        var latent = Self.gaussianNoise(count: latentDim * latentLength)
        let latentMask = [Float](repeating: 1, count: latentLength)
        let totalStep = try ORTValue(float: [Float(steps)], shape: [1])

        for step in 0..<steps {
            let denoised = try sessions.vectorEstimator.run(
                withInputs: [
                    "noisy_latent": try ORTValue(float: latent, shape: [1, latentDim, latentLength]),
                    "text_emb": textEmb,
                    "style_ttl": try style.ttlValue(),
                    "latent_mask": try ORTValue(float: latentMask, shape: [1, 1, latentLength]),
                    "text_mask": textMask,
                    "current_step": try ORTValue(float: [Float(step)], shape: [1]),
                    "total_step": totalStep,
                ],
                outputNames: ["denoised_latent"],
                runOptions: nil
            )
            latent = try denoised["denoised_latent"]!.floats()
        }

        // 4 — latent to waveform
        let vocoded = try sessions.vocoder.run(
            withInputs: ["latent": try ORTValue(float: latent, shape: [1, latentDim, latentLength])],
            outputNames: ["wav_tts"],
            runOptions: nil
        )
        return try vocoded["wav_tts"]!.floats()
    }

    // MARK: - Tokenizing

    /// Text to model IDs.
    ///
    /// NFKD first, which is load-bearing rather than tidiness: the model indexes *unicode
    /// scalars*, and Hangul in composed form is one scalar per syllable where the model expects
    /// decomposed jamo. Skipping it silently mistokenises Korean while leaving English fine.
    private func tokenize(_ text: String) -> [Int64] {
        text.decomposedStringWithCompatibilityMapping.unicodeScalars.map { scalar in
            let value = Int(scalar.value)
            return value < indexer.count ? indexer[value] : -1
        }
    }

    // MARK: - Noise

    /// Standard normal samples, Box–Muller.
    ///
    /// `Float.random` is uniform; feeding uniform noise to a model trained to denoise Gaussian
    /// noise gives a quieter, duller result rather than an obvious failure — which is the kind
    /// of bug that survives a listening test.
    private static func gaussianNoise(count: Int) -> [Float] {
        var out = [Float]()
        out.reserveCapacity(count)
        for _ in 0..<count {
            let u1 = Float.random(in: 0.0001...1.0)
            let u2 = Float.random(in: 0.0...1.0)
            out.append((-2 * log(u1)).squareRoot() * cos(2 * .pi * u2))
        }
        return out
    }
}

// MARK: - ORTValue Helpers

extension ORTValue {

    /// A float tensor from a flat array.
    convenience init(float values: [Float], shape: [Int]) throws {
        let data = NSMutableData(bytes: values, length: values.count * MemoryLayout<Float>.size)
        try self.init(tensorData: data, elementType: .float, shape: shape.map(NSNumber.init))
    }

    /// An int64 tensor from a flat array.
    convenience init(int64 values: [Int64], shape: [Int]) throws {
        let data = NSMutableData(bytes: values, length: values.count * MemoryLayout<Int64>.size)
        try self.init(tensorData: data, elementType: .int64, shape: shape.map(NSNumber.init))
    }

    /// The tensor's contents as floats.
    func floats() throws -> [Float] {
        let data = try tensorData() as Data
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
