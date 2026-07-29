//
//  SupertonicAssetStore.swift
//  SupertonicTTS
//
//  Fetches the ONNX graphs and voice styles on first use, so the engine matches
//  the FluidAudio-backed ones: construct it, call prepare(), and it sorts itself out.
//

import Foundation

/// Downloads and caches the Supertonic assets.
///
/// The weights are not bundled — ~400 MB would land in every app whether or not the user ever
/// picks this voice — so they are fetched once into Application Support and reused.
public struct SupertonicAssetStore: Sendable {

    /// One file to fetch, with the size used to weight download progress.
    private struct Asset: Sendable {
        let path: String
        let bytes: Int64
    }

    /// Everything the engine needs.
    ///
    /// Sizes are the published ones and are used only to weight the progress bar. The vector
    /// estimator alone is roughly two thirds of the download, so weighting by file *count*
    /// would sit at 60% for most of the wait and then finish in a rush.
    private static let assets: [Asset] = [
        Asset(path: "onnx/tts.json", bytes: 8_253),
        Asset(path: "onnx/unicode_indexer.json", bytes: 277_676),
        Asset(path: "onnx/duration_predictor.onnx", bytes: 3_700_147),
        Asset(path: "onnx/text_encoder.onnx", bytes: 36_416_150),
        Asset(path: "onnx/vector_estimator.onnx", bytes: 256_534_781),
        Asset(path: "onnx/vocoder.onnx", bytes: 101_424_195),
    ] + ["F1", "F2", "F3", "F4", "F5", "M1", "M2", "M3", "M4", "M5"].map {
        Asset(path: "voice_styles/\($0).json", bytes: 292_046)
    }

    private static let remote = URL(string: "https://huggingface.co/Supertone/supertonic-3/resolve/main")!

    /// Where assets are cached.
    ///
    /// Application Support rather than Caches: the system may evict Caches under disk
    /// pressure, and re-downloading 400 MB because the disk got tight is a poor surprise.
    public static var defaultDirectory: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "SupertonicTTS", isDirectory: true)
            .appendingPathComponent("Supertonic", isDirectory: true)
    }

    /// Total download size in bytes, for a confirmation prompt.
    public static var downloadBytes: Int64 { assets.reduce(0) { $0 + $1.bytes } }

    /// Whether everything is already on disk.
    public static func isInstalled(at directory: URL) -> Bool {
        assets.allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.path).path)
        }
    }

    /// Fetch anything missing.
    ///
    /// Resumable in the only sense that matters here: each file is checked individually, so an
    /// interrupted download picks up at the next file rather than starting the whole 400 MB
    /// again. Files are written to a temporary name and moved into place only once complete, so
    /// an interrupted *file* is never mistaken for a finished one on the next run.
    public static func install(
        at directory: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let total = Double(downloadBytes)
        var completed: Double = 0

        for asset in assets {
            let destination = directory.appendingPathComponent(asset.path)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if FileManager.default.fileExists(atPath: destination.path) {
                completed += Double(asset.bytes)
                onProgress?(min(completed / total, 1))
                continue
            }

            try Task.checkCancellation()

            let source = remote.appendingPathComponent(asset.path)
            let (temporary, response) = try await URLSession.shared.download(from: source)
            defer { try? FileManager.default.removeItem(at: temporary) }

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw SupertonicAssetError.downloadFailed(asset.path)
            }

            // `replaceItemAt` needs an existing destination; on a clean install there isn't one.
            _ = try? FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }

            completed += Double(asset.bytes)
            onProgress?(min(completed / total, 1))
        }

        onProgress?(1)
    }
}

// MARK: - Errors

/// Why the assets could not be fetched.
public enum SupertonicAssetError: LocalizedError {

    /// A file could not be downloaded.
    case downloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .downloadFailed(let path):
            return "Could not download \(path) for Supertonic."
        }
    }
}
