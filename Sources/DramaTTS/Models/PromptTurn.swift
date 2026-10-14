//
//  PromptTurn.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Text and the audio that speaks it: a cloning reference, or an earlier
/// chunk kept as history so the next chunk continues in the same voice.
struct PromptTurn<Codes> {

    /// What is said.
    var text: String

    /// The codes `[codebooks, frames]` of saying it.
    var codes: Codes
}
