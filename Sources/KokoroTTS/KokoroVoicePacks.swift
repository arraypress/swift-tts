//
//  KokoroVoicePacks.swift
//  KokoroTTS
//
//  Created by David Sherlock on 2026.
//

import Foundation
import SpeechSynthesizer

// FluidAudio also exports a `TTSError`; ours is the one we throw.
private typealias TTSError = SpeechSynthesizer.TTSError

/// Fetching the voice packs the CoreML conversion did not ship.
///
/// The engine loads a voice from `<cache>/ANE/<id>.bin`: 510 × 256 little-endian
/// float32, 522,240 bytes exactly. The converted model repository contains one
/// of those — `af_heart` — and nothing else in English.
///
/// The original `hexgrad/Kokoro-82M` has all fifty-four, as `voices/<id>.pt`.
/// A `.pt` is a zip around a pickle and its raw tensor storage, and for these
/// files the storage entry is **the same 522,240 bytes, stored uncompressed,
/// little-endian** — byte-for-byte what the engine wants. So converting one is
/// not a conversion at all: it is finding the right offset and copying.
///
/// That means no PyTorch, no Python, and no dependency — just a zip local
/// header to step over.
public enum KokoroVoicePacks {

    /// Where the original packs live.
    static let repository = "hexgrad/Kokoro-82M"

    /// The folder the engine reads packs from.
    ///
    /// Mirrors FluidAudio's own layout — `~/.cache/fluidaudio` on macOS and
    /// Application Support elsewhere — because the pack has to land where the
    /// engine will look, not somewhere tidy.
    public static var cacheDirectory: URL {
        let manager = FileManager.default
        #if os(macOS)
        let root = manager.homeDirectoryForCurrentUser.appendingPathComponent(".cache/fluidaudio")
        #else
        let root = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("fluidaudio")
        #endif
        return root.appendingPathComponent("Models/kokoro-82m-coreml/ANE")
    }

    /// 510 rows × 256 columns of float32.
    static let expectedBytes = 510 * 256 * 4

    // MARK: Fetching

    /// Makes sure `<directory>/<voice>.bin` exists, downloading it if not.
    ///
    /// - Parameters:
    ///   - voice: A Kokoro voice id, e.g. `bf_emma`.
    ///   - directory: The engine's `ANE/` folder.
    /// - Returns: The pack's location, whether it was already there or fetched.
    @discardableResult
    public static func ensure(
        _ voice: String,
        in directory: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {

        guard KokoroVoices.exists(voice) else {
            throw TTSError.unsupportedVoice(voice)
        }
        let destination = directory.appendingPathComponent("\(voice).bin")

        // Already there and the right size. A truncated pack from an
        // interrupted download would otherwise be trusted and produce noise.
        if let size = try? FileManager.default.attributesOfItem(
            atPath: destination.path
        )[.size] as? Int, size == expectedBytes {
            return destination
        }

        let url = URL(string:
            "https://huggingface.co/\(repository)/resolve/main/voices/\(voice).pt")!
        let archive: Data
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw TTSError.modelDownloadFailed("\(voice): HTTP \(http.statusCode)")
            }
            archive = data
        } catch let error as TTSError {
            throw error
        } catch {
            throw TTSError.modelDownloadFailed("\(voice): \(error.localizedDescription)")
        }
        onProgress?(0.8)

        let pack = try extractTensor(from: archive, voice: voice)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        // Written beside the target and moved, so an interrupted write cannot
        // leave a half a pack that later looks present.
        let staging = directory.appendingPathComponent(".\(voice).bin.partial")
        try pack.write(to: staging)
        _ = try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: staging, to: destination)

        onProgress?(1.0)
        return destination
    }

    // MARK: Reading the archive

    /// The raw tensor bytes out of a `.pt`.
    ///
    /// Read through the central directory at the end of the archive rather
    /// than by walking local headers from the front. PyTorch writes these
    /// files streaming, with the data-descriptor flag set (`0x08`), which
    /// means **the size in every local header is zero** and the real one
    /// trails the data. Walking forward from the first header therefore steps
    /// zero bytes and lands in the middle of the payload.
    ///
    /// The central directory carries the true sizes and offsets, so it is the
    /// only honest way in.
    static func extractTensor(from archive: Data, voice: String) throws -> Data {
        let wanted = "\(voice)/data/0"

        // End-of-central-directory record: "PK\u{05}\u{06}", within the last
        // 64 KB (the comment field's maximum) of the file.
        let signature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        let horizon = max(0, archive.count - 65_557)
        var endRecord: Int?
        var scan = archive.count - 22
        while scan >= horizon {
            if archive[relative: scan] == signature[0],
               archive[relative: scan + 1] == signature[1],
               archive[relative: scan + 2] == signature[2],
               archive[relative: scan + 3] == signature[3] {
                endRecord = scan
                break
            }
            scan -= 1
        }
        guard let endRecord else {
            throw TTSError.modelDownloadFailed("\(voice): not a zip archive")
        }

        let entryCount = Int(archive.readUInt16(at: endRecord + 10))
        var cursor = Int(archive.readUInt32(at: endRecord + 16))

        for _ in 0..<entryCount {
            guard cursor + 46 <= archive.count,
                  archive[relative: cursor] == 0x50,
                  archive[relative: cursor + 1] == 0x4B,
                  archive[relative: cursor + 2] == 0x01,
                  archive[relative: cursor + 3] == 0x02 else { break }

            let method = archive.readUInt16(at: cursor + 10)
            let compressed = Int(archive.readUInt32(at: cursor + 20))
            let nameLength = Int(archive.readUInt16(at: cursor + 28))
            let extraLength = Int(archive.readUInt16(at: cursor + 30))
            let commentLength = Int(archive.readUInt16(at: cursor + 32))
            let localHeader = Int(archive.readUInt32(at: cursor + 42))

            let nameStart = cursor + 46
            guard nameStart + nameLength <= archive.count else { break }
            let name = String(
                decoding: archive[relative: nameStart..<nameStart + nameLength], as: UTF8.self
            )

            if name == wanted {
                guard method == 0 else {
                    throw TTSError.modelDownloadFailed(
                        "\(voice): the tensor is compressed, which these files have never been"
                    )
                }
                // The local header's own name and extra lengths, which differ
                // from the central directory's.
                guard localHeader + 30 <= archive.count else {
                    throw TTSError.modelDownloadFailed("\(voice): the archive is truncated")
                }
                let localNameLength = Int(archive.readUInt16(at: localHeader + 26))
                let localExtraLength = Int(archive.readUInt16(at: localHeader + 28))
                let start = localHeader + 30 + localNameLength + localExtraLength

                guard start + compressed <= archive.count else {
                    throw TTSError.modelDownloadFailed("\(voice): the archive is truncated")
                }
                let body = Data(archive[relative: start..<start + compressed])
                guard body.count == expectedBytes else {
                    throw TTSError.modelDownloadFailed(
                        "\(voice): expected \(expectedBytes) bytes, found \(body.count)"
                    )
                }
                return body
            }
            cursor = nameStart + nameLength + extraLength + commentLength
        }
        throw TTSError.modelDownloadFailed("\(voice): no tensor found in the archive")
    }
}

// MARK: - Reading little-endian fields

private extension Data {

    /// Indexing from the start of the value rather than the buffer.
    ///
    /// A `Data` slice keeps the parent's indices, so treating one as
    /// zero-based reads the wrong bytes or traps.
    subscript(relative offset: Int) -> UInt8 {
        self[startIndex + offset]
    }

    subscript(relative range: Range<Int>) -> Data {
        self[(startIndex + range.lowerBound)..<(startIndex + range.upperBound)]
    }

    func readUInt16(at offset: Int) -> UInt16 {
        UInt16(self[relative: offset]) | (UInt16(self[relative: offset + 1]) << 8)
    }

    func readUInt32(at offset: Int) -> UInt32 {
        UInt32(self[relative: offset])
            | (UInt32(self[relative: offset + 1]) << 8)
            | (UInt32(self[relative: offset + 2]) << 16)
            | (UInt32(self[relative: offset + 3]) << 24)
    }
}
