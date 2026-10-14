//
//  OmniVoiceLicence.swift
//  OmniVoiceTTS
//
//  Created by David Sherlock on 2026.
//
//  OmniVoice is two sets of weights under two licences, neither of them open:
//
//    • The speech model (k2-fsa/OmniVoice) — CC BY-NC, "due to constraints
//      from its training data (e.g., Emilia)"; the model card names no version.
//      Its code is Apache-2.0; the weights are what run. (The mlx-community
//      conversion's card says apache-2.0 — that is the code's licence, not
//      the weights'.)
//    • The audio tokenizer (Boson AI's Higgs Audio 2 codec) — the Boson Higgs
//      Audio 2 Community License, derived from the Meta Llama 3 Community
//      License: ship both texts and the NOTICE lines, display the "Built with
//      Higgs Materials…" line, follow Llama 3's Acceptable Use Policy, never
//      use outputs to improve another large language model, and above 100,000
//      annual active users ask Boson for a licence.
//
//  And the model card forbids unauthorised voice cloning and impersonation.
//

import Foundation

/// The terms OmniVoice runs under, and the version string an engine must name.
public enum OmniVoiceLicence {

    /// The licences, as one string; ``OmniVoiceEngine`` refuses to start
    /// unless this is passed to it, so a program cannot run the model
    /// without naming its terms.
    public static let version = "OmniVoice CC BY-NC + Boson Higgs Audio 2 Community License"

    /// The model card, which states the weights' licence.
    public static let modelCardURL = URL(string:
        "https://huggingface.co/k2-fsa/OmniVoice/blob/c5fdb5ccb189668d56333f77ba2629f4cd7535f4/README.md")!

    /// Creative Commons' page for the licence family the weights name.
    public static let ccByNCURL = URL(string: "https://creativecommons.org/licenses/by-nc/4.0/")!

    /// Llama 3's Acceptable Use Policy, which the Higgs licence incorporates.
    public static let acceptableUseURL = URL(string: "https://llama.meta.com/llama3/use-policy")!

    /// The line the Higgs licence requires on anything built with it (§1.b.i).
    public static let attribution = """
        Built with Higgs Materials licensed from Boson AI USA, Inc., Copyright Boson AI USA, Inc., \
        All Rights Reserved and Meta Llama 3 licensed under the Meta Llama 3 Community License, \
        Copyright Meta Platforms, Inc., All Rights Reserved. Based on Meta Llama 3.
        """

    /// The NOTICE text the Higgs licence requires with every copy (§1.b.iii).
    public static let notice = """
        OmniVoice (k2-fsa/OmniVoice) — speech model weights licensed under CC BY-NC \
        (Creative Commons Attribution-NonCommercial), Copyright Xiaomi Corp. and the OmniVoice authors.
        Its audio tokenizer is Boson AI's Higgs Audio 2 codec:
        Meta Llama 3 is licensed under the Meta Llama 3 Community License, Copyright © Meta Platforms, Inc. \
        All Rights Reserved.
        Boson Higgs Audio 2 is licensed under the Boson Community License, Copyright © Boson AI USA, Inc. \
        All Rights Reserved.
        \(attribution)
        """

    /// The terms in plain words.
    public static let summary = """
        OmniVoice runs under two licences, neither of them open:
          • The speech model's weights: CC BY-NC (Attribution-NonCommercial; the model
            card names no version) — non-commercial use only.
          • Its audio tokenizer, Boson AI's Higgs Audio 2: the Boson Higgs Audio 2
            Community License, built on the Meta Llama 3 Community License —
              · Llama 3's Acceptable Use Policy applies (\(acceptableUseURL.absoluteString));
              · never use its output to improve another large language model;
              · above 100,000 annual active users, a licence from Boson AI is required;
              · anything you ship with it displays the line below and carries both licences.
          • The model card: no unauthorised voice cloning or impersonation, no fraud.
            Clone only your own voice, or one you have permission to use.
        \(attribution)
        Model card: \(modelCardURL.absoluteString)
        """
}
