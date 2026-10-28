//
//  OmniModelFolder.swift
//  OmniVoiceTTS
//
//  Created by David Sherlock on 2026.
//
//  mlx-audio-swift's OmniVoice port loads only from its own Hugging Face
//  cache — `HubCache.default`/mlx-audio/<owner_name>/ — and downloads into it
//  when a file is missing. This engine never downloads: the caller fetches a
//  pinned, checksummed copy (the `speak` CLI does), so the folder's files are
//  linked into that cache under a name no real repository has, loaded, and
//  unlinked.
//  A missing file is reported before the port can try to fetch anything.
//
//  The port also prints its progress ("Using cached model at: …") to standard
//  output, which is where a CLI writes WAV bytes; loading runs with stdout
//  pointed at /dev/null. Its failures are thrown, not printed, so nothing is
//  lost; the pinned, checksummed folder is what guarantees every weight is there.
//

import Foundation
import HuggingFace
import MLX
import MLXAudioTTS
import MLXNN
import StdoutSilencer

/// The model folder: what it must hold, what it can do, and loading it.
enum OmniModelFolder {

    /// Files the engine reads; every one must be present.
    static let requiredFiles = [
        "config.json", "model.safetensors", "tokenizer.json", "tokenizer_config.json",
        "audio_tokenizer/config.json", "audio_tokenizer/model.safetensors",
    ]

    /// The first required file missing from `folder`, if any.
    static func missingFile(in folder: URL) -> String? {
        requiredFiles.first { !FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }

    /// Whether the audio tokenizer carries the semantic encoder that encoding
    /// a reference needs — the full-precision conversion does, the bfloat16
    /// one strips it. Read from the safetensors header, without loading.
    static func canEncodeReferences(in folder: URL) -> Bool {
        let file = folder.appendingPathComponent("audio_tokenizer/model.safetensors")
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 8), prefix.count == 8 else { return false }
        let length = prefix.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).littleEndian }
        guard length > 0, length < 64 << 20, let header = try? handle.read(upToCount: Int(length)) else { return false }
        return String(decoding: header, as: UTF8.self).contains("\"semantic_model.")
    }

    /// Loads the model from `folder` without touching the network.
    static func load(_ folder: URL) async throws -> OmniVoiceModel {
        if let missing = missingFile(in: folder) { throw OmniVoiceError.modelMissing("no \(missing) in \(folder.path)") }
        let name = "omnivoice-local-\(UUID().uuidString.prefix(8).lowercased())"
        let linkParent = HubCache.default.cacheDirectory.appendingPathComponent("mlx-audio", isDirectory: true)
        let link = linkParent.appendingPathComponent("arraypress_\(name)")
        // A folder of links rather than one link to the folder: the port lists
        // the folder by URL, which does not follow a link in its last component.
        // Folders made for it are removed again if nothing else moved in.
        var created: [URL] = []
        var ancestor = linkParent
        while !FileManager.default.fileExists(atPath: ancestor.path) {
            created.append(ancestor)
            ancestor = ancestor.deletingLastPathComponent()
        }
        try FileManager.default.createDirectory(at: link, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: link)
            for folder in created { _ = rmdir(folder.path) }   // only if empty
        }
        for entry in try FileManager.default.contentsOfDirectory(atPath: folder.path) where !entry.hasPrefix(".") {
            try FileManager.default.createSymbolicLink(at: link.appendingPathComponent(entry),
                                                       withDestinationURL: folder.appendingPathComponent(entry))
        }
        let model = try await StandardOutput.silenced {
            try await OmniVoiceModel.fromPretrained("arraypress/\(name)")
        }
        if let base = model.tokenizer { model.tokenizer = TagAwareTokenizer(base: base) }
        return model
    }
}

extension OmniModelFolder {

    /// Casts the speech model's floating-point weights (not the audio
    /// tokenizer's, which is a separate module) to `dtype`.
    static func convertSpeechModel(_ model: OmniVoiceModel, to dtype: DType) {
        let converted = model.parameters().flattened()
            .filter { key, _ in !key.hasPrefix("audioTokenizer") && !key.hasPrefix("audio_tokenizer") }
            .map { key, value in (key, value.dtype.isFloatingPoint ? value.asType(dtype) : value) }
        model.update(parameters: ModuleParameters.unflattened(converted))
        eval(model)
    }
}
