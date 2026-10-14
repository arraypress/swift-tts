//
//  DramaPrompt.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  The reference-bracket-v1 prompt as segments. The system block depends only
//  on the references, so its cache state can be reused across chunks.
//

import Foundation

/// Builds Drama 3's prompt.
enum DramaPrompt {

    /// The template version this port writes.
    static let templateVersion = "reference-bracket-v1"

    /// The prompt's segments, and how many of them form the system block.
    ///
    /// - Parameters:
    ///   - references: Voices to clone, each with its transcript.
    ///   - history: Earlier chunks of this request (the first and the previous).
    ///   - target: The chunk to speak.
    static func segments<Codes>(references: [PromptTurn<Codes>], history: [PromptTurn<Codes>],
                                target: String) -> (segments: [PromptSegment<Codes>], systemCount: Int) {
        var segments: [PromptSegment<Codes>] = [.text("<|im_start|>system\n")]
        if references.isEmpty {
            segments.append(.text("convert the provided text to speech"))
        } else {
            segments.append(.text("convert the provided text to speech reference to the following:"))
            for (index, reference) in references.enumerated() {
                segments.append(.text("\n\n[Reference \(index + 1)]\nText: "
                                      + "\(DramaText.referenceTranscript(reference.text))\nSpeech: "))
                segments.append(.audio(reference.codes))
            }
        }
        segments.append(.text("<|im_end|>\n"))
        let systemCount = segments.count
        for turn in history {
            segments += [.text("<|im_start|>user\n"), .text(DramaText.withSpeakerTag(turn.text)),
                         .text("<|im_end|>\n"), .text("<|im_start|>assistant\n<|voice|>"), .audio(turn.codes),
                         .text("<|im_end|>\n")]
        }
        segments += [.text("<|im_start|>user\n"), .text(DramaText.withSpeakerTag(target)), .text("<|im_end|>\n"),
                     .text("<|im_start|>assistant\n<|voice|>")]
        return (segments, systemCount)
    }
}
