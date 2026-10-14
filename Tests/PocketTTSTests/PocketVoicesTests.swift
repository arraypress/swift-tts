//
//  PocketVoicesTests.swift
//  PocketTTS
//
//  Created by David Sherlock on 2026.
//

import SpeechSynthesizer
import Testing
@testable import PocketTTS

@Test func theDefaultVoiceIsCommercialSafe() throws {
    let voice = try #require(PocketVoices.voices().first { $0.id == PocketVoices.defaultID })
    #expect(voice.isCommercialUseAllowed)
    #expect(voice.license == "CC-BY-4.0")
    #expect(!PocketVoices.nonCommercialIDs.contains(PocketVoices.defaultID))
}

/// Expresso (cosette) and EARS (jean) are CC BY-NC 4.0.
@Test func cosetteAndJeanAreFlaggedNonCommercial() {
    #expect(PocketVoices.nonCommercialIDs == ["cosette", "jean"])
    for voice in PocketVoices.voices() where !voice.isCommercialUseAllowed {
        #expect(voice.license == "CC-BY-NC-4.0")
        #expect(voice.name.contains("non-commercial"))
    }
}

@Test func everyPresetIsAPocketVoiceWithAUniqueID() {
    let voices = PocketVoices.voices()
    #expect(voices.count == 21)
    #expect(Set(voices.map(\.id)).count == voices.count)
    #expect(voices.allSatisfy { $0.model == .pocket })
    #expect(voices.first { $0.id == "peter_yearsley" }?.name == "Peter Yearsley")
}
