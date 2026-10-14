//
//  PromptSegment.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One piece of the reference-bracket-v1 prompt: text tokenized on its own,
/// or audio codes laid in as frame rows.
enum PromptSegment<Codes> {

    /// A string, tokenized alone — tokenizing the joined prompt changes the ids at the seams.
    case text(String)

    /// Audio codes `[codebooks, frames]`.
    case audio(Codes)
}
