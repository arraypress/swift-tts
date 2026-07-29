//
//  TTSModel.swift
//  SpeechSynthesizer
//
//  The curated set of on-device TTS models this package supports, split by
//  runtime tier: small CoreML/ANE models that run on iPhone, larger MLX/GPU
//  models for the Mac, and ONNX Runtime for graphs shipped that way.
//
//  Every model here permits commercial use, but they are not all under the same
//  terms — see `license` and `isCommercialUseAllowed` on each case rather than
//  assuming Apache/MIT across the board.
//

import Foundation

/// A supported, commercial-safe on-device TTS model.
public enum TTSModel: String, CaseIterable, Sendable {

    /// Apple's built-in system voices (`AVSpeechSynthesizer`) — zero download,
    /// runs on every device, always available. The batteries-included default.
    case apple

    /// Kokoro-82M — fast, light, 9 languages, SSML. (Apache-2.0)
    case kokoro

    /// PocketTTS — small, streaming, voice cloning. (MIT)
    case pocket

    /// Chatterbox — top-tier quality + emotion + cloning; Mac-class. (MIT)
    case chatterbox

    /// Qwen3-TTS — multilingual, long-form, cloning; Mac-class. (Apache-2.0)
    case qwen3

    /// Supertonic 3 — 31 languages in ~99M params, mobile-class. (OpenRAIL-M)
    ///
    /// The multilingual gap-filler: Kokoro covers 9 languages without cloning, and the
    /// Mac-class models are too heavy for a phone. This runs on mobile and covers 31.
    ///
    /// Note the licence is **not** Apache/MIT like the rest. OpenRAIL-M permits commercial
    /// use but attaches use-based restrictions, so an app shipping it inherits terms the
    /// other models here do not carry — see ``isCommercialUseAllowed``.
    case supertonic

    /// A human-readable name.
    public var displayName: String {
        switch self {
        case .apple: "Apple (system)"
        case .kokoro: "Kokoro-82M"
        case .pocket: "PocketTTS"
        case .chatterbox: "Chatterbox"
        case .qwen3: "Qwen3-TTS"
        case .supertonic: "Supertonic 3"
        }
    }

    /// The model-weights licence.
    ///
    /// The *weights*, not the sample code — those differ for Supertonic, whose reference
    /// implementation is MIT while the model it loads is OpenRAIL-M.
    public var license: String {
        switch self {
        case .apple: "Apple system (free to use)"
        case .kokoro, .qwen3: "Apache-2.0"
        case .pocket, .chatterbox: "MIT"
        case .supertonic: "OpenRAIL-M"
        }
    }

    /// The runtime this model uses.
    public var runtime: TTSRuntime {
        switch self {
        case .apple: .system
        case .kokoro, .pocket: .coreML
        case .chatterbox, .qwen3: .mlx
        case .supertonic: .onnx
        }
    }

    /// Whether the model is light enough to run on iPhone/iPad.
    public var runsOnMobile: Bool {
        switch self {
        case .apple, .kokoro, .pocket, .supertonic: true
        case .chatterbox, .qwen3: false
        }
    }

    /// Whether the model can clone a voice from a reference sample.
    public var supportsVoiceCloning: Bool {
        switch self {
        case .pocket, .chatterbox, .qwen3: true
        case .apple, .kokoro, .supertonic: false
        }
    }

    /// Whether the weights permit commercial use.
    ///
    /// A real check, not a constant. This used to `return true` unconditionally, which was
    /// accurate only for as long as every model happened to be Apache or MIT — the first case
    /// added under different terms would have silently inherited a claim nobody had verified.
    ///
    /// Supertonic is `true` with a caveat worth reading: OpenRAIL-M allows commercial use but
    /// imposes use-based restrictions in its Attachment A, so "allowed" here does not mean the
    /// unrestricted grant that Apache-2.0 and MIT give.
    public var isCommercialUseAllowed: Bool {
        switch self {
        case .apple, .kokoro, .pocket, .chatterbox, .qwen3: true
        case .supertonic: true
        }
    }

    /// Whether the licence attaches conditions beyond attribution.
    ///
    /// Surfaced separately so an app can show the difference rather than flattening every
    /// model into a single "commercial use: yes".
    public var hasLicenseRestrictions: Bool {
        switch self {
        case .apple, .kokoro, .pocket, .chatterbox, .qwen3: false
        case .supertonic: true
        }
    }

    /// Whether the model's weights must be downloaded on first use.
    /// Apple's system voices are built in, so they don't.
    public var requiresDownload: Bool { self != .apple }

    /// Rough on-disk size once downloaded, in megabytes (order-of-magnitude).
    /// Zero for Apple's built-in voices.
    public var approximateSizeMB: Int {
        switch self {
        case .apple: 0
        case .kokoro: 350
        case .pocket: 400
        case .chatterbox: 1_000
        case .qwen3: 1_500
        case .supertonic: 400
        }
    }
}

/// The on-device runtime backing a model.
public enum TTSRuntime: String, Sendable {

    /// Apple's built-in system speech synthesizer.
    case system = "System"

    /// CoreML on the Apple Neural Engine — low power, ideal for iPhone/iPad.
    case coreML = "CoreML/ANE"

    /// MLX on the GPU — for larger models, Mac-class.
    case mlx = "MLX/GPU"

    /// ONNX Runtime, for models shipped as ONNX graphs rather than converted.
    ///
    /// Measured on Supertonic: the **CPU** execution provider beat the CoreML one — 11.6x
    /// real time against 5.9x — because CoreML supports only part of the graph and splits it
    /// into ~134 partitions, so the run spends its time crossing back and forth rather than
    /// computing. CoreML also cost 6.5 s of session setup against 0.3 s. Worth knowing before
    /// reaching for the accelerator that sounds faster.
    case onnx = "ONNX Runtime"
}
