//
//  DramaLicence.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  Drama 3's weights are not under an open-source licence. They are under the
//  Fish Audio Community License: free for research and non-commercial use;
//  commercial use only by an organisation with under US$500,000 a year in
//  revenue; never as a hosted text-to-speech or voice-cloning service; and
//  never to clone a real person's voice without their consent.
//

import Foundation

/// The terms Drama 3 runs under, and the version string an engine must name.
public enum DramaLicence {

    /// The licence version; ``DramaEngine`` refuses to start unless this is
    /// passed to it, so a program cannot run the model without naming its terms.
    public static let version = "Fish Audio Community License v1.0"

    /// The licence text, in the model's own repository.
    public static let url = URL(string:
        "https://huggingface.co/stickerdaniel/drama-3-mlx-4bit/blob/06469309e6a7bff6b32c191fb220e25017c04fff/LICENSE")!

    /// The terms in plain words.
    public static let summary = """
        Fish Audio Drama 3 is licensed under the \(version):
          • Free for research and non-commercial use.
          • Commercial use only if your organisation's annual revenue is under US$500,000.
          • Never as a hosted service where others generate speech or clone voices from
            text or samples they supply (speech for your own content is fine).
          • Never to imitate an identifiable person's voice without their consent.
          • Anything you ship or publish with it says "Built with Fish Audio".
        Full text: \(url.absoluteString) (also LICENSE beside the model).
        """
}
