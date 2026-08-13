//
//  KokoroVoicePackTests.swift
//  KokoroTTS
//
//  Created by David Sherlock on 2026.
//

import Foundation
import Testing
@testable import KokoroTTS

// MARK: - The voice list

@Test func everyEnglishVoiceIsOffered() {
    // The list was five, four of which 404'd at synthesis. Kokoro has 28
    // English voices and all of them work.
    #expect(KokoroVoices.english.count == 28)
    #expect(KokoroVoices.exists("af_heart"))
    #expect(KokoroVoices.exists("bf_emma"))
    #expect(KokoroVoices.exists("af_aoede"))
    #expect(!KokoroVoices.exists("nonsense"))
}

/// The English CoreML pipeline has an English phoneme vocabulary. A Japanese
/// pack would load and make a sound, but not the one anybody wanted.
@Test func otherLanguagesAreNotOffered() {
    #expect(!KokoroVoices.exists("jf_alpha"))
    #expect(!KokoroVoices.exists("zf_xiaobei"))
    #expect(KokoroVoices.ids.contains("jf_alpha"), "still known, just not offered")
}

@Test func voiceIdsDecodeIntoSomethingReadable() {
    let emma = KokoroVoices.describe("bf_emma")
    #expect(emma.language == "en-GB")
    #expect(emma.name == "Emma (UK, female)")

    let adam = KokoroVoices.describe("am_adam")
    #expect(adam.language == "en-US")
    #expect(adam.name == "Adam (US, male)")
}

@Test func theListHasNoDuplicates() {
    #expect(Set(KokoroVoices.ids).count == KokoroVoices.ids.count)
}

// MARK: - Reading a .pt

/// PyTorch writes these archives streaming, with the data-descriptor flag set,
/// which leaves **zero** in every local header's size field. A reader that
/// walks local headers therefore steps zero bytes and lands mid-payload — so
/// the central directory is the only honest way in. This builds an archive
/// shaped exactly like that.
@Test func aStreamingWrittenArchiveIsReadCorrectly() throws {
    let payload = Data((0..<KokoroVoicePacks.expectedBytes).map { UInt8($0 % 251) })
    let archive = ZipBuilder.streaming(name: "bf_emma/data/0", payload: payload)

    let extracted = try KokoroVoicePacks.extractTensor(from: archive, voice: "bf_emma")
    #expect(extracted == payload)
}

@Test func aPackOfTheWrongSizeIsRefused() {
    // A truncated download must not be accepted and cached as a voice.
    let short = Data(repeating: 7, count: 1024)
    let archive = ZipBuilder.streaming(name: "bf_emma/data/0", payload: short)
    #expect(throws: (any Error).self) {
        try KokoroVoicePacks.extractTensor(from: archive, voice: "bf_emma")
    }
}

@Test func anArchiveWithoutTheTensorIsRefused() {
    let archive = ZipBuilder.streaming(name: "bf_emma/version", payload: Data("3".utf8))
    #expect(throws: (any Error).self) {
        try KokoroVoicePacks.extractTensor(from: archive, voice: "bf_emma")
    }
}

@Test func somethingThatIsNotAZipIsRefused() {
    #expect(throws: (any Error).self) {
        try KokoroVoicePacks.extractTensor(from: Data("not a zip".utf8), voice: "bf_emma")
    }
}

// MARK: - A zip written the way PyTorch writes them

enum ZipBuilder {

    /// One stored entry, with the data-descriptor flag set and zeroed sizes in
    /// the local header — exactly what `torch.save` produces.
    static func streaming(name: String, payload: Data) -> Data {
        var out = Data()
        let nameBytes = Data(name.utf8)

        let localOffset = 0
        out.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])   // local header
        out.append(uint16(20))                              // version
        out.append(uint16(0x0808))                          // flags: data descriptor
        out.append(uint16(0))                               // stored
        out.append(uint16(0)); out.append(uint16(0))        // time, date
        out.append(uint32(0))                               // crc, unknown here
        out.append(uint32(0))                               // compressed size: zero
        out.append(uint32(0))                               // uncompressed size: zero
        out.append(uint16(UInt16(nameBytes.count)))
        out.append(uint16(0))                               // extra
        out.append(nameBytes)
        out.append(payload)

        // Data descriptor, which is where the real sizes live.
        out.append(contentsOf: [0x50, 0x4B, 0x07, 0x08])
        out.append(uint32(0))
        out.append(uint32(UInt32(payload.count)))
        out.append(uint32(UInt32(payload.count)))

        let centralOffset = out.count
        out.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])   // central directory
        out.append(uint16(20)); out.append(uint16(20))
        out.append(uint16(0x0808))
        out.append(uint16(0))                               // stored
        out.append(uint16(0)); out.append(uint16(0))
        out.append(uint32(0))
        out.append(uint32(UInt32(payload.count)))           // the true size
        out.append(uint32(UInt32(payload.count)))
        out.append(uint16(UInt16(nameBytes.count)))
        out.append(uint16(0)); out.append(uint16(0))
        out.append(uint16(0)); out.append(uint16(0))
        out.append(uint32(0))
        out.append(uint32(UInt32(localOffset)))
        out.append(nameBytes)

        let centralSize = out.count - centralOffset
        out.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])   // end of central directory
        out.append(uint16(0)); out.append(uint16(0))
        out.append(uint16(1)); out.append(uint16(1))
        out.append(uint32(UInt32(centralSize)))
        out.append(uint32(UInt32(centralOffset)))
        out.append(uint16(0))
        return out
    }

    private static func uint16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    private static func uint32(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF),
        ])
    }
}
