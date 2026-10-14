//
//  TagAwareTokenizer.swift
//  OmniVoiceTTS
//
//  Created by David Sherlock on 2026.
//
//  The reference tokenizes each non-verbal tag on its own
//  (`_tokenize_with_nonverbal_tags`), "to guarantee consistent token IDs
//  regardless of surrounding language context" — the tags are not special
//  tokens, and Qwen's pre-tokenizer would otherwise glue the space before a
//  tag to its bracket (" [" instead of "["), giving the model ids it never
//  saw a tag as. The MLX port encodes the text whole; this wrapper puts the
//  reference's rule back without forking the port.
//

import Foundation
import Tokenizers

/// A tokenizer that encodes OmniVoice's non-verbal tags standalone.
struct TagAwareTokenizer: Tokenizer {

    let base: any Tokenizer

    /// The text split around supported tags, tags kept as their own pieces.
    static func segments(_ text: String) -> [String] {
        let tags = OmniTags.supported.map { "[\($0)]" }
        var pieces: [String] = []
        var rest = Substring(text)
        while let (range, _) = tags.compactMap({ tag in rest.range(of: tag).map { ($0, tag) } })
            .min(by: { $0.0.lowerBound < $1.0.lowerBound }) {
            if range.lowerBound > rest.startIndex { pieces.append(String(rest[rest.startIndex..<range.lowerBound])) }
            pieces.append(String(rest[range]))
            rest = rest[range.upperBound...]
        }
        if !rest.isEmpty { pieces.append(String(rest)) }
        return pieces
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        let pieces = Self.segments(text)
        guard pieces.count > 1 else { return base.encode(text: text, addSpecialTokens: addSpecialTokens) }
        return pieces.flatMap { base.encode(text: $0, addSpecialTokens: false) }
    }

    func encode(text: String) -> [Int] { encode(text: text, addSpecialTokens: true) }
    func callAsFunction(_ text: String, addSpecialTokens: Bool) -> [Int] {
        encode(text: text, addSpecialTokens: addSpecialTokens)
    }
    func tokenize(text: String) -> [String] { base.tokenize(text: text) }
    func decode(tokens: [Int]) -> String { base.decode(tokens: tokens) }
    func decode(tokens: [Int], skipSpecialTokens: Bool) -> String {
        base.decode(tokens: tokens, skipSpecialTokens: skipSpecialTokens)
    }
    func convertTokenToId(_ token: String) -> Int? { base.convertTokenToId(token) }
    func convertTokensToIds(_ tokens: [String]) -> [Int?] { base.convertTokensToIds(tokens) }
    func convertIdToToken(_ id: Int) -> String? { base.convertIdToToken(id) }
    func convertIdsToTokens(_ ids: [Int]) -> [String?] { base.convertIdsToTokens(ids) }
    var bosToken: String? { base.bosToken }
    var bosTokenId: Int? { base.bosTokenId }
    var eosToken: String? { base.eosToken }
    var eosTokenId: Int? { base.eosTokenId }
    var unknownToken: String? { base.unknownToken }
    var unknownTokenId: Int? { base.unknownTokenId }
    var hasChatTemplate: Bool { base.hasChatTemplate }

    func applyChatTemplate(messages: [Message]) throws -> [Int] { try base.applyChatTemplate(messages: messages) }
    func applyChatTemplate(messages: [Message], tools: [ToolSpec]?) throws -> [Int] {
        try base.applyChatTemplate(messages: messages, tools: tools)
    }
    func applyChatTemplate(messages: [Message], tools: [ToolSpec]?,
                           additionalContext: [String: any Sendable]?) throws -> [Int] {
        try base.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
    }
    func applyChatTemplate(messages: [Message], chatTemplate: ChatTemplateArgument) throws -> [Int] {
        try base.applyChatTemplate(messages: messages, chatTemplate: chatTemplate)
    }
    func applyChatTemplate(messages: [Message], chatTemplate: String) throws -> [Int] {
        try base.applyChatTemplate(messages: messages, chatTemplate: chatTemplate)
    }
    func applyChatTemplate(messages: [Message], chatTemplate: ChatTemplateArgument?, addGenerationPrompt: Bool,
                           truncation: Bool, maxLength: Int?, tools: [ToolSpec]?) throws -> [Int] {
        try base.applyChatTemplate(messages: messages, chatTemplate: chatTemplate,
                                   addGenerationPrompt: addGenerationPrompt, truncation: truncation,
                                   maxLength: maxLength, tools: tools)
    }
    func applyChatTemplate(messages: [Message], chatTemplate: ChatTemplateArgument?, addGenerationPrompt: Bool,
                           truncation: Bool, maxLength: Int?, tools: [ToolSpec]?,
                           additionalContext: [String: any Sendable]?) throws -> [Int] {
        try base.applyChatTemplate(messages: messages, chatTemplate: chatTemplate,
                                   addGenerationPrompt: addGenerationPrompt, truncation: truncation,
                                   maxLength: maxLength, tools: tools, additionalContext: additionalContext)
    }
}
