//
//  NeuralG2P.swift
//  KokoroTTS
//
//  Created by David Sherlock on 2026.
//
//  The fallback for words Misaki's lexicon does not have — mostly names.
//
//  FluidAudio ships a small BART encoder-decoder that spells a word in
//  Kokoro's phonemes (`G2PEncoder.mlmodelc`, `G2PDecoder.mlmodelc`,
//  `g2p_vocab.json`, downloaded with the model). FluidAudio's own wrapper
//  (`G2PModel`, Apache-2.0) is internal, so this is that wrapper again,
//  reading the same files: greedy decoding, BART's position offset of two,
//  at most 64 steps.
//
//  It is bad at common words ("is" → "ice") and that is why the lexicon
//  goes first; for a name nobody wrote down it is the best guess there is.
//

import CoreML
import Foundation
import SpeechSynthesizer

// FluidAudio also exports a `TTSError`; ours is the one we throw.
private typealias TTSError = SpeechSynthesizer.TTSError

/// The neural grapheme-to-phoneme model, for words no lexicon has.
actor NeuralG2P {

    private let directory: URL
    private var encoder: MLModel?
    private var decoder: MLModel?
    private var graphemes: [Character: Int32] = [:]
    private var phonemes: [Int32: String] = [:]
    private var bos: Int32 = 1
    private var eos: Int32 = 2
    private var unknown: Int32 = 3

    /// - Parameter directory: The folder holding the two models and their vocabulary.
    init(directory: URL) {
        self.directory = directory
    }

    /// `word`'s phonemes, or `nil` if the model produced none.
    func phonemes(for word: String) throws -> String? {
        try loadIfNeeded()
        guard let encoder, let decoder else { return nil }

        let input: [Int32] = [bos] + word.lowercased().map { graphemes[$0] ?? unknown } + [eos]
        let encoderInput = try MLMultiArray(shape: [1, NSNumber(value: input.count)], dataType: .int32)
        for (index, id) in input.enumerated() { encoderInput[[0, NSNumber(value: index)]] = NSNumber(value: id) }
        let encoded = try encoder.prediction(from: MLDictionaryFeatureProvider(
            dictionary: ["input_ids": MLFeatureValue(multiArray: encoderInput)]))
        guard let hidden = encoded.featureValue(for: "encoder_hidden_states")?.multiArrayValue else { return nil }

        var output: [Int32] = [bos]
        for _ in 0..<64 {
            let length = output.count
            let ids = try MLMultiArray(shape: [1, NSNumber(value: length)], dataType: .int32)
            let positions = try MLMultiArray(shape: [1, NSNumber(value: length)], dataType: .int32)
            let mask = try MLMultiArray(shape: [1, NSNumber(value: length), NSNumber(value: length)], dataType: .float32)
            for index in 0..<length {
                ids[[0, NSNumber(value: index)]] = NSNumber(value: output[index])
                positions[[0, NSNumber(value: index)]] = NSNumber(value: Int32(index + 2))
                for column in 0..<length {
                    mask[[0, NSNumber(value: index), NSNumber(value: column)]] = NSNumber(value: column > index ? -1e4 : 0)
                }
            }
            let decoded = try decoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                "decoder_input_ids": MLFeatureValue(multiArray: ids),
                "encoder_hidden_states": MLFeatureValue(multiArray: hidden),
                "position_ids": MLFeatureValue(multiArray: positions),
                "causal_mask": MLFeatureValue(multiArray: mask),
            ]))
            guard let logits = decoded.featureValue(for: "logits")?.multiArrayValue,
                  let size = logits.shape.last?.intValue else { return nil }
            var best: Int32 = 0
            var bestValue = -Float.infinity
            for token in 0..<size {
                let value = logits[[0, NSNumber(value: length - 1), NSNumber(value: token)]].floatValue
                if value > bestValue {
                    bestValue = value
                    best = Int32(token)
                }
            }
            if best == eos { break }
            output.append(best)
        }

        let special: Set<Int32> = [0, bos, eos, unknown]
        let spelled = output.filter { !special.contains($0) }.compactMap { phonemes[$0] }.joined()
        return spelled.isEmpty ? nil : spelled
    }

    private func loadIfNeeded() throws {
        guard encoder == nil || decoder == nil else { return }
        let vocabulary = directory.appendingPathComponent("g2p_vocab.json")
        guard let data = try? Data(contentsOf: vocabulary),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let toID = json["grapheme_to_id"] as? [String: Int],
              let toPhoneme = json["id_to_phoneme"] as? [String: String] else {
            throw TTSError.modelDownloadFailed("Kokoro's G2P vocabulary is missing or unreadable: \(vocabulary.path)")
        }
        graphemes = Dictionary(uniqueKeysWithValues: toID.compactMap { key, value in
            key.count == 1 ? (key.first!, Int32(value)) : nil
        })
        phonemes = Dictionary(uniqueKeysWithValues: toPhoneme.compactMap { key, value in
            Int32(key).map { ($0, value) }
        })
        bos = (json["bos_token_id"] as? Int).map(Int32.init) ?? 1
        eos = (json["eos_token_id"] as? Int).map(Int32.init) ?? 2
        unknown = (json["unk_token_id"] as? Int).map(Int32.init) ?? 3

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        do {
            encoder = try MLModel(contentsOf: directory.appendingPathComponent("G2PEncoder.mlmodelc"),
                                  configuration: configuration)
            decoder = try MLModel(contentsOf: directory.appendingPathComponent("G2PDecoder.mlmodelc"),
                                  configuration: configuration)
        } catch {
            throw TTSError.modelDownloadFailed("Kokoro's G2P model would not load: \(error.localizedDescription)")
        }
    }
}
