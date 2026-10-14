//
//  DramaPipeline.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  One Drama 3 request, end to end: chunk the text, build each chunk's prompt
//  as frame rows, prefill, then decode frame by frame — the backbone samples
//  the main token (EOS or a semantic token), the tower samples codebooks 1…9,
//  and the frame is fed back. Pieces are decoded by the codec as they arrive.
//  A port of mlx-audio's fish_drama3 (drama3.py), kept to its recipe.
//

import Foundation
import MLX
import MLXAudioCodecs
import MLXNN
import SpeechSynthesizer
import Tokenizers

/// The loaded model and the decode loop. Owned by ``DramaEngine``, which
/// serialises every call into it.
final class DramaPipeline {

    /// Rows fed to the backbone per prefill pass.
    static let prefillChunk = 256

    /// Most voices whose prompt state is kept between requests.
    static let keptVoices = 4

    /// Times one chunk may go back to its last speech and sample again after
    /// running into dead air. A runaway (no end-of-speech, steady hiss) hit 9
    /// of 20 measured clips in both this port and the Python reference; each
    /// rewind resamples from the end of the last good audio.
    static let maxRewinds = 3

    let configuration: DramaConfiguration
    let network: DramaNetwork
    let codec: FishS1DAC
    let tokenizer: any Tokenizer
    let candidateIDs: MLXArray

    private var voices: [(key: String, voice: VoiceState)] = []

    /// Codec samples per second (44 100).
    var sampleRate: Double { Double(codec.sampleRate) }

    /// Samples per frame (2048).
    var frameLength: Int { codec.frameLength }

    // MARK: - Loading

    init(folder: URL) async throws {
        let configURL = folder.appendingPathComponent("config.json")
        guard let data = FileManager.default.contents(atPath: configURL.path) else {
            throw DramaError.modelMissing("no config.json in \(folder.path)")
        }
        let configuration: DramaConfiguration
        do { configuration = try JSONDecoder().decode(DramaConfiguration.self, from: data) } catch {
            throw DramaError.unsupportedModel("config.json: \(error)")
        }
        try Self.check(configuration)
        self.configuration = configuration

        let network = DramaNetwork(configuration)
        try WeightLoading.load(network, from: folder, configuration: configuration)
        self.network = network

        let codecURL = folder.appendingPathComponent("codec.safetensors")
        guard FileManager.default.fileExists(atPath: codecURL.path) else {
            throw DramaError.modelMissing("no codec.safetensors in \(folder.path)")
        }
        let codec = buildFishS1DAC()
        do {
            let weights = codec.sanitize(weights: try loadArrays(url: codecURL))
            try codec.update(parameters: ModuleParameters.unflattened(weights), verify: .noUnusedKeys)
        } catch {
            throw DramaError.unsupportedModel("codec.safetensors: \(error)")
        }
        eval(codec.parameters())
        self.codec = codec

        do { tokenizer = try await AutoTokenizer.from(modelFolder: folder) } catch {
            throw DramaError.modelMissing("tokenizer: \(error)")
        }
        let lastCode = configuration.tower.vocabularySize - 1
        for (token, expected) in [("<|semantic:0|>", configuration.semanticStartTokenID),
                                  ("<|semantic:\(lastCode)|>", configuration.semanticEndTokenID),
                                  ("<|im_end|>", configuration.eosTokenID)]
        where tokenizer.convertTokenToId(token) != expected {
            throw DramaError.unsupportedModel("the tokenizer and config disagree on \(token)")
        }
        let band = (configuration.semanticStartTokenID ... configuration.semanticEndTokenID).map(Int32.init)
        candidateIDs = MLXArray(band + [Int32(configuration.eosTokenID)])
        eval(candidateIDs)
    }

    /// Refuses a checkpoint this port would load but compute wrongly.
    static func check(_ configuration: DramaConfiguration) throws {
        guard configuration.speechTemplateVersion == DramaPrompt.templateVersion else {
            throw DramaError.unsupportedModel("speech template \(configuration.speechTemplateVersion)")
        }
        let text = configuration.text
        let expected = (0 ..< text.layers).map { ($0 + 1) % text.fullAttentionInterval == 0
            ? "full_attention" : "linear_attention" }
        guard text.layerTypes == expected else {
            throw DramaError.unsupportedModel("expected three linear-attention layers per full one")
        }
    }

    // MARK: - Prompt

    /// Token ids of one prompt string, tokenized alone.
    func tokens(_ text: String) -> [Int] {
        tokenizer.encode(text: text, addSpecialTokens: false)
    }

    /// The prompt as frame rows `[T, 1 + codebooks]` and how many lead rows
    /// form the system block. Text rows are `[token, 0, …]`; audio rows are
    /// `[c0 + semantic_begin, c0…c9]`.
    func frames(references: [PromptTurn<MLXArray>], history: [PromptTurn<MLXArray>],
                target: String) throws -> (frames: MLXArray, systemRows: Int) {
        if let problem = DramaText.problem(with: target, location: "text") { throw DramaError.invalidText(problem) }
        for (index, reference) in references.enumerated() {
            if let problem = DramaText.problem(with: reference.text, location: "reference \(index + 1)") {
                throw DramaError.invalidReference(problem)
            }
        }
        let (segments, systemCount) = DramaPrompt.segments(references: references, history: history, target: target)
        let width = 1 + configuration.tower.codebooks
        var rows: [Int32] = []
        var systemRows = 0
        for (index, segment) in segments.enumerated() {
            let before = rows.count
            switch segment {
            case .text(let string):
                for id in tokens(string) {
                    rows.append(Int32(id))
                    rows += [Int32](repeating: 0, count: width - 1)
                }
            case .audio(let codes):
                let count = codes.dim(1)
                let flat = codes.asType(.int32).asArray(Int32.self)
                for frame in 0 ..< count {
                    let column = (0 ..< configuration.tower.codebooks).map { flat[$0 * count + frame] }
                    rows.append(column[0] + Int32(configuration.semanticStartTokenID))
                    rows += column
                }
            }
            if index < systemCount { systemRows += (rows.count - before) / width }
        }
        return (MLXArray(rows, [rows.count / width, width]), systemRows)
    }

    /// Codes `[codebooks, frames]` for a reference clip.
    func encode(_ reference: DramaReference) throws -> MLXArray {
        let samples = try Resampling.resample(reference.audio.samples, from: reference.audio.sampleRate,
                                              to: sampleRate)
        guard samples.count >= frameLength else {
            throw DramaError.invalidReference("the reference clip is too short to clone from")
        }
        let (indices, lengths) = codec.encode(MLXArray(samples).reshaped(1, 1, -1))
        let length = Int(lengths[0].item(Int32.self))
        let codes = indices[0, 0..., ..<length].asType(.int32)
        eval(codes)
        return codes
    }

    /// The voice for these references, from the cache when it was used recently.
    func voice(for references: [DramaReference]) throws -> VoiceState {
        let key = Self.key(for: references)
        if let index = voices.firstIndex(where: { $0.key == key }) {
            let entry = voices.remove(at: index)
            voices.append(entry)
            return entry.voice
        }
        let voice = VoiceState(references: try references.map { PromptTurn(text: $0.transcript, codes: try encode($0)) })
        voices.append((key, voice))
        if voices.count > Self.keptVoices { voices.removeFirst() }
        return voice
    }

    static func key(for references: [DramaReference]) -> String {
        var hasher = Hasher()
        for reference in references {
            hasher.combine(reference.audio.samples.count)
            hasher.combine(reference.audio.sampleRate)
            for sample in reference.audio.samples { hasher.combine(sample.bitPattern) }
            hasher.combine(reference.transcript)
        }
        return String(hasher.finalize())
    }

    // MARK: - Decoding

    /// Feeds rows `[start, stop)` to both caches; returns row stop−1's hidden
    /// state `[1, 1, D]`. The tower is teacher-forced with the following row.
    func prefill(_ frames: MLXArray, caches: Caches, start: Int, stop: Int) -> MLXArray {
        let batched = frames.expandedDimensions(axis: 0)
        let last = frames.dim(0) - 1
        var hidden = MLXArray(0)
        for begin in stride(from: start, to: stop, by: Self.prefillChunk) {
            let end = min(begin + Self.prefillChunk, stop)
            hidden = network.backbone.model(embeddings: network.embed(batched[0..., begin ..< end]),
                                            cache: caches.backbone)
            let labelled = min(end, last)
            if labelled > begin {
                network.tower.prefill(hidden[0..., ..<(labelled - begin)], frames: batched[0..., begin ..< labelled],
                                      nextFrames: batched[0..., (begin + 1) ..< (labelled + 1)],
                                      caches: caches.tower)
            }
            eval([hidden] + caches.state)
        }
        return hidden[0..., (-1)...]
    }

    /// Fresh caches holding the system block, copied from the voice's snapshot.
    func startCaches(_ frames: MLXArray, systemRows: Int, voice: VoiceState) -> Caches {
        if voice.prefix == nil {
            let caches = Caches(backbone: network.backbone.model.makeCache(), tower: network.tower.makeCache())
            _ = prefill(frames, caches: caches, start: 0, stop: systemRows)
            voice.prefix = caches.copy()
        }
        return voice.prefix!.copy()
    }

    /// One frame, all lazy: the frame `[1, 1, 11]`, the next hidden state,
    /// the main-token history, and the main token `[1]`.
    func step(hidden: MLXArray, frame: MLXArray, history: MLXArray, caches: Caches,
              settings: DramaSettings) -> (frame: MLXArray, hidden: MLXArray, history: MLXArray, main: MLXArray) {
        let tower = network.tower
        let logits = network.semanticHead(hidden[0..., 0]).asType(.float32)
        let first = candidateIDs[DramaSampling.sample(logits, temperature: settings.temperature, topK: settings.topK,
                                                      topP: settings.topP)]
        let retry = candidateIDs[DramaSampling.sample(logits, temperature: DramaSampling.repetitionTemperature,
                                                      topK: DramaSampling.repetitionTopK,
                                                      topP: DramaSampling.repetitionTopP)]
        let repeated = (history.expandedDimensions(axis: 0) .== first.expandedDimensions(axis: 1)).any(axis: -1)
        let main = which(repeated .&& tower.isSemantic(first), retry, first)
        let c0 = clip(main - Int32(tower.semanticBegin), min: 0, max: tower.vocabularySize - 1)
        let semantic = tower.isSemantic(main).expandedDimensions(axis: 1)
        let codes = tower.residualCodes(hidden, c0: c0.expandedDimensions(axis: 1), semantic: semantic, frame: frame,
                                        caches: caches.tower) { headLogits in
            DramaSampling.sample(headLogits[0..., 0], temperature: settings.temperature, topK: settings.topK,
                                 topP: settings.topP).expandedDimensions(axis: 1)
        }
        let newFrame = concatenated([main.expandedDimensions(axis: 1).asType(.int32)]
                                    + codes.map { $0.asType(.int32) }, axis: -1).expandedDimensions(axis: 1)
        let nextHidden = network.backbone.model(embeddings: network.embed(newFrame), cache: caches.backbone)
        let nextHistory = concatenated([history[1...], main.asType(history.dtype)])
        return (newFrame, nextHidden, nextHistory, main)
    }

    /// Audio for frames `[from, frames.count)`, decoded by the request's stream.
    func decode(_ frames: [MLXArray], from: Int, stream: CodecStream) -> [Float] {
        guard from < frames.count else { return [] }
        let codes = stacked(Array(frames[from...]), axis: 1).expandedDimensions(axis: 0)
        let piece = stream.step(codes).reshaped(-1).asType(.float32)
        eval(piece)
        return piece.asArray(Float.self)
    }

    // MARK: - Generation

    /// Speaks `text`, handing each decoded piece to `emit` as it is ready.
    ///
    /// - Parameters:
    ///   - text: The text, cues inline (`[whispers]`, `<|speaker:1|>`).
    ///   - references: Voices to clone.
    ///   - settings: Sampling and stopping.
    ///   - isCancelled: Polled once per frame.
    ///   - emit: Receives each piece.
    /// - Returns: What the request cost.
    func generate(_ text: String, references: [DramaReference], settings: DramaSettings,
                  isCancelled: () -> Bool, emit: (DramaChunk) throws -> Void) throws -> DramaReport {
        if let problem = DramaText.problem(with: text, location: "text") { throw DramaError.invalidText(problem) }
        if let seed = settings.seed { MLXRandom.seed(seed) }
        Memory.peakMemory = 0
        let started = Date()
        let voice = try voice(for: references)
        let chunks = DramaText.split(text)
        var report = DramaReport(chunks: chunks.count, frames: 0, cappedChunks: 0, silencedChunks: 0, rewinds: 0,
                                 firstAudioSeconds: nil, peakMemoryBytes: 0)
        var pinned: PromptTurn<MLXArray>?
        var latest: PromptTurn<MLXArray>?
        var allFrames: [MLXArray] = []
        let codecStream = CodecStream(codec: codec)
        let interval = max(1, settings.streamingFrames)

        func send(_ samples: [Float], segment: Int) throws {
            guard !samples.isEmpty else { return }
            if report.firstAudioSeconds == nil { report.firstAudioSeconds = Date().timeIntervalSince(started) }
            try emit(DramaChunk(samples: samples, sampleRate: sampleRate, segment: segment, isFinal: false,
                                report: nil))
        }

        for (index, chunk) in chunks.enumerated() {
            let history = [pinned, latest].compactMap { $0 }
            let (frames, systemRows) = try self.frames(references: voice.references, history: history, target: chunk)
            let maxFrames = settings.maxFramesPerChunk ?? FrameBudget.maxFrames(for: chunk)
            let rule = SilenceRule()
            var gate = settings.stopsOnSilence ? QuietGate(rule: rule, sampleRate: sampleRate) : nil
            let chunkStart = allFrames.count
            var decoded = chunkStart

            var caches = startCaches(frames, systemRows: systemRows, voice: voice)
            let hidden = prefill(frames, caches: caches, start: systemRows, stop: frames.dim(0))
            let historyStart = max(0, frames.dim(0) - DramaSampling.repetitionWindow)
            // The last point everything before which was speech: where a rewind resumes.
            var good = Checkpoint(caches: caches.copy(), hidden: hidden,
                                  frame: frames[(frames.dim(0) - 1)...].expandedDimensions(axis: 0),
                                  history: frames[historyStart..., 0], frames: allFrames.count,
                                  codec: codecStream.state)
            var candidate = good
            var rewinds = 0
            var end = ChunkEnd.capped
            var pending = step(hidden: good.hidden, frame: good.frame, history: good.history, caches: caches,
                               settings: settings)
            asyncEval(pending.frame, pending.hidden, pending.history, pending.main)
            // Rewinds throw frames away; this bounds the work they can cost.
            var steps = 0
            while allFrames.count - chunkStart < maxFrames && steps < 2 * maxFrames {
                if isCancelled() { throw DramaError.cancelled }
                steps += 1
                let current = pending
                let completesPiece = allFrames.count + 1 - decoded >= interval
                if completesPiece && gate != nil {
                    // The state after this frame, taken before the next step is queued.
                    candidate = Checkpoint(caches: caches.copy(), hidden: current.hidden, frame: current.frame,
                                           history: current.history, frames: allFrames.count + 1,
                                           codec: codecStream.state)
                }
                // Queued before this frame's EOS is read, so the GPU never waits on the host.
                pending = step(hidden: current.hidden, frame: current.frame, history: current.history,
                               caches: caches, settings: settings)
                asyncEval(pending.frame, pending.hidden, pending.history, pending.main)
                if Int(current.main.item(Int32.self)) == configuration.eosTokenID {
                    end = .endOfSpeech
                    break
                }
                allFrames.append(current.frame[0, 0, 1...])
                guard completesPiece else { continue }
                let piece = decode(allFrames, from: decoded, stream: codecStream)
                decoded = allFrames.count
                guard gate != nil else {
                    try send(piece, segment: index)
                    continue
                }
                let (out, stop) = gate!.pass(piece)
                if !stop {
                    try send(out, segment: index)
                    if gate!.held.isEmpty {
                        candidate.codec = codecStream.state
                        good = candidate
                    }
                    continue
                }
                if rewinds < Self.maxRewinds {
                    // Dead air: the model has lost its way. Back to the end of
                    // the last speech and sample again from there.
                    rewinds += 1
                    report.rewinds += 1
                    caches = good.caches.copy()
                    allFrames.removeLast(allFrames.count - good.frames)
                    decoded = good.frames
                    codecStream.state = good.codec
                    gate = QuietGate(rule: rule, sampleRate: sampleRate)
                    pending = step(hidden: good.hidden, frame: good.frame, history: good.history, caches: caches,
                                   settings: settings)
                    asyncEval(pending.frame, pending.hidden, pending.history, pending.main)
                    continue
                }
                try send(out, segment: index)
                // Out of rewinds: end the chunk, and keep the dead air out of
                // the history the next chunk is prompted with.
                allFrames.removeLast(allFrames.count - good.frames)
                decoded = allFrames.count
                end = .deadAir
                break
            }
            switch end {
            case .capped: report.cappedChunks += 1
            case .deadAir: report.silencedChunks += 1
            case .endOfSpeech: break
            }
            if end != .deadAir {
                var tail = decode(allFrames, from: decoded, stream: codecStream)
                if gate != nil { tail = gate!.flush() + tail }
                try send(tail, segment: index)
            }
            let produced = allFrames.count - chunkStart
            report.frames += produced
            if produced > 0 {
                let turn = PromptTurn(text: chunk, codes: stacked(Array(allFrames[chunkStart...]), axis: 1))
                if pinned == nil { pinned = turn } else { latest = turn }
            }
        }
        report.peakMemoryBytes = Memory.peakMemory
        return report
    }
}

extension DramaPipeline {

    /// The backbone's and the tower's caches for one chunk.
    struct Caches {
        var backbone: [LayerCache]
        var tower: [AttentionCache]

        /// Every array the caches hold.
        var state: [MLXArray] { backbone.flatMap(\.state) + tower.flatMap(\.state) }

        /// Independent copies.
        func copy() -> Caches {
            Caches(backbone: backbone.map { $0.copy() }, tower: tower.map { $0.copy() })
        }
    }

    /// Everything needed to carry on generating from one point of a chunk.
    struct Checkpoint {
        var caches: Caches
        var hidden: MLXArray
        var frame: MLXArray
        var history: MLXArray
        var frames: Int
        var codec: CodecStream.State
    }

    /// How a chunk ended.
    enum ChunkEnd {
        /// The model emitted end-of-speech.
        case endOfSpeech
        /// The frame budget ran out.
        case capped
        /// Dead air persisted through every rewind.
        case deadAir
    }

    /// A voice's encoded references and, once built, its system-block caches.
    final class VoiceState {
        let references: [PromptTurn<MLXArray>]
        var prefix: Caches?

        init(references: [PromptTurn<MLXArray>]) {
            self.references = references
        }
    }
}
