//
//  Tower.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  Drama 3's audio tower samples codebooks 1…9 of every frame. Each of its 13
//  layers keeps a key/value cache across frames; all run at the same temporal
//  position, and the codebook index picks the layer, not the RoPE position.
//  A frame row is [main token, c0, …, c9], c0 being the main token's offset in
//  the semantic band.
//

import MLX
import MLXNN

/// The codebook-MTP audio tower: 4 shared enrichment layers + 9 residual ones.
final class Tower: Module {

    let vocabularySize: Int
    let codebooks: Int
    let backboneCodebooks: Int
    let semanticBegin: Int
    let semanticEnd: Int

    @ModuleInfo(key: "codebook_embeddings") var codebookEmbeddings: Embedding
    @ModuleInfo(key: "shared_layers") var sharedLayers: [TowerLayer]
    @ModuleInfo(key: "residual_layers") var residualLayers: [TowerLayer]
    @ModuleInfo(key: "codebook_heads") var codebookHeads: [Linear]

    /// - Parameters:
    ///   - config: The tower's shape.
    ///   - semanticBegin: `<|semantic:0|>`'s id.
    ///   - semanticEnd: The last semantic token's id.
    init(_ config: TowerConfiguration, semanticBegin: Int, semanticEnd: Int) {
        vocabularySize = config.vocabularySize
        codebooks = config.codebooks
        backboneCodebooks = config.backboneCodebooks
        self.semanticBegin = semanticBegin
        self.semanticEnd = semanticEnd
        _codebookEmbeddings.wrappedValue = Embedding(embeddingCount: config.vocabularySize * config.codebooks,
                                                     dimensions: config.dim)
        _sharedLayers.wrappedValue = (0 ..< config.sharedEnrichmentLayers).map { _ in
            TowerLayer(config, enrichment: true)
        }
        _residualLayers.wrappedValue = (0 ..< config.codebooks - 1).map { _ in TowerLayer(config, enrichment: false) }
        _codebookHeads.wrappedValue = (0 ..< config.codebooks - 1).map { _ in
            Linear(config.dim, config.vocabularySize, bias: false)
        }
        super.init()
    }

    /// Fresh caches, one per layer.
    func makeCache() -> [AttentionCache] {
        (sharedLayers + residualLayers).map { _ in AttentionCache() }
    }

    /// Whether ids are in the semantic band.
    func isSemantic(_ tokens: MLXArray) -> MLXArray {
        (tokens .>= semanticBegin) .&& (tokens .<= semanticEnd)
    }

    /// The sum of codebooks `first..<end`'s embeddings for frames `[B, T, 11]`.
    func embeddingSum(_ frames: MLXArray, first: Int, end: Int) -> MLXArray {
        let offsets = MLXArray(Int32(first) ..< Int32(end)) * Int32(vocabularySize)
        let rows = frames[.ellipsis, (1 + first) ..< (1 + end)] + offsets
        return codebookEmbeddings(rows).sum(axis: -2)
    }

    /// Backbone input: audio rows add the first residual codebooks to the token
    /// embedding and rescale; text rows keep the token embedding.
    func embedBackbone(_ frames: MLXArray, text: MLXArray) -> MLXArray {
        let count = backboneCodebooks
        let scale = MLXArray(Float(1 + count).squareRoot()).reciprocal().asType(text.dtype)
        let mixed = (text + embeddingSum(frames, first: 1, end: 1 + count)) * scale
        let semantic = isSemantic(frames[.ellipsis, 0]).expandedDimensions(axis: -1)
        return which(semantic, mixed, text)
    }

    private func enrich(_ hidden: MLXArray, c0: MLXArray, semantic: MLXArray, frames: MLXArray,
                        caches: [AttentionCache]) -> MLXArray {
        // The first enrichment layer also sees the codebooks the backbone input left out.
        var unseen = embeddingSum(frames, first: 1 + backboneCodebooks, end: codebooks)
        unseen = which(isSemantic(frames[.ellipsis, 0]).expandedDimensions(axis: -1), unseen, zeros(like: unseen))
        var hidden = hidden
        for (index, layer) in sharedLayers.enumerated() {
            hidden = layer(hidden, codes: c0, semantic: semantic, cache: caches[index],
                           extra: index == 0 ? unseen : nil)
        }
        return hidden
    }

    /// Teacher-forces the caches over a prompt; row t is labelled by row t+1.
    func prefill(_ hidden: MLXArray, frames: MLXArray, nextFrames: MLXArray, caches: [AttentionCache]) {
        let semantic = isSemantic(nextFrames[.ellipsis, 0])
        var hidden = enrich(hidden, c0: nextFrames[.ellipsis, 1], semantic: semantic, frames: frames, caches: caches)
        let offset = sharedLayers.count
        for (index, layer) in residualLayers.enumerated() {
            hidden = layer(hidden, codes: nextFrames[.ellipsis, index + 1], semantic: semantic,
                           cache: caches[offset + index])
        }
    }

    /// Teacher-forced head logits' top-1 for each residual codebook — the
    /// parity probe's view of ``prefill(_:frames:nextFrames:caches:)``.
    func teacherForcedTop1(_ hidden: MLXArray, frames: MLXArray, nextFrames: MLXArray,
                           caches: [AttentionCache]) -> MLXArray {
        let semantic = isSemantic(nextFrames[.ellipsis, 0])
        var hidden = enrich(hidden, c0: nextFrames[.ellipsis, 1], semantic: semantic, frames: frames, caches: caches)
        let offset = sharedLayers.count
        var tops: [MLXArray] = []
        for (index, (layer, head)) in zip(residualLayers, codebookHeads).enumerated() {
            hidden = layer(hidden, codes: nextFrames[.ellipsis, index + 1], semantic: semantic,
                           cache: caches[offset + index])
            tops.append(argMax(head(hidden).asType(.float32), axis: -1))
        }
        return stacked(tops, axis: -1)
    }

    /// Codes c0…c9 of one frame, sampling c1…c9 with `sample(logits)`.
    func residualCodes(_ hidden: MLXArray, c0: MLXArray, semantic: MLXArray, frame: MLXArray,
                       caches: [AttentionCache], sample: (MLXArray) -> MLXArray) -> [MLXArray] {
        var hidden = enrich(hidden, c0: c0, semantic: semantic, frames: frame, caches: caches)
        var codes = [c0]
        let offset = sharedLayers.count
        for (index, (layer, head)) in zip(residualLayers, codebookHeads).enumerated() {
            hidden = layer(hidden, codes: codes[codes.count - 1], semantic: semantic, cache: caches[offset + index])
            codes.append(sample(head(hidden)))
        }
        return codes
    }
}
