//
//  TTSModel.swift
//  SpeechSynthesizer
//
//  The curated set of on-device TTS models this package supports — chosen to be
//  commercial-safe (Apache/MIT weights only) and split by runtime tier: small
//  CoreML/ANE models that run on iPhone, and larger MLX/GPU models for the Mac.
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

    /// A human-readable name.
    public var displayName: String {
        switch self {
        case .apple: "Apple (system)"
        case .kokoro: "Kokoro-82M"
        case .pocket: "PocketTTS"
        case .chatterbox: "Chatterbox"
        case .qwen3: "Qwen3-TTS"
        }
    }

    /// The model-weights license (all curated to permit commercial use).
    public var license: String {
        switch self {
        case .apple: "Apple system (free to use)"
        case .kokoro, .qwen3: "Apache-2.0"
        case .pocket, .chatterbox: "MIT"
        }
    }

    /// The runtime this model uses.
    public var runtime: TTSRuntime {
        switch self {
        case .apple: .system
        case .kokoro, .pocket: .coreML
        case .chatterbox, .qwen3: .mlx
        }
    }

    /// Whether the model is light enough to run on iPhone/iPad.
    public var runsOnMobile: Bool {
        switch self {
        case .apple, .kokoro, .pocket: true
        case .chatterbox, .qwen3: false
        }
    }

    /// Whether the model can clone a voice from a reference sample.
    public var supportsVoiceCloning: Bool {
        switch self {
        case .pocket, .chatterbox, .qwen3: true
        case .apple, .kokoro: false
        }
    }

    /// Every model here is usable in a commercial product.
    public var isCommercialUseAllowed: Bool { true }

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
}
