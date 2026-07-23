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

    /// Kokoro-82M — fast, light, 9 languages, SSML. The default. (Apache-2.0)
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
        case .kokoro: "Kokoro-82M"
        case .pocket: "PocketTTS"
        case .chatterbox: "Chatterbox"
        case .qwen3: "Qwen3-TTS"
        }
    }

    /// The model-weights license (all curated to permit commercial use).
    public var license: String {
        switch self {
        case .kokoro, .qwen3: "Apache-2.0"
        case .pocket, .chatterbox: "MIT"
        }
    }

    /// The runtime this model uses.
    public var runtime: TTSRuntime {
        switch self {
        case .kokoro, .pocket: .coreML
        case .chatterbox, .qwen3: .mlx
        }
    }

    /// Whether the model is light enough to run on iPhone/iPad.
    public var runsOnMobile: Bool {
        switch self {
        case .kokoro, .pocket: true
        case .chatterbox, .qwen3: false
        }
    }

    /// Whether the model can clone a voice from a reference sample.
    public var supportsVoiceCloning: Bool {
        switch self {
        case .pocket, .chatterbox, .qwen3: true
        case .kokoro: false
        }
    }

    /// Every model here is curated to permit commercial use.
    public var isCommercialUseAllowed: Bool { true }

    /// Rough on-disk size once downloaded, in megabytes (order-of-magnitude).
    public var approximateSizeMB: Int {
        switch self {
        case .kokoro: 350
        case .pocket: 400
        case .chatterbox: 1_000
        case .qwen3: 1_500
        }
    }
}

/// The on-device runtime backing a model.
public enum TTSRuntime: String, Sendable {

    /// CoreML on the Apple Neural Engine — low power, ideal for iPhone/iPad.
    case coreML = "CoreML/ANE"

    /// MLX on the GPU — for larger models, Mac-class.
    case mlx = "MLX/GPU"
}
