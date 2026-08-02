import SwiftUI
import AVFoundation
import SpeechSynthesizer
import KokoroTTS
import PocketTTS
import MLXTTS

enum EngineChoice: String, CaseIterable, Identifiable {
    case apple      = "Apple (system)"
    case kokoro     = "Kokoro · CoreML/ANE"
    case kokoroMLX  = "Kokoro · MLX/GPU (Misaki G2P)"
    case pocket     = "PocketTTS · CoreML"
    case chatterbox = "Chatterbox · MLX/GPU (cloning)"
    case qwen3      = "Qwen3-TTS · MLX/GPU"

    var id: String { rawValue }

    func makeEngine() -> any TTSEngine {
        switch self {
        case .apple:      return AppleEngine()
        case .kokoro:     return KokoroEngine()
        case .kokoroMLX:  return MLXEngine.kokoro()
        case .pocket:     return PocketEngine()
        case .chatterbox: return MLXEngine.chatterbox()
        case .qwen3:      return MLXEngine.qwen3()
        }
    }

    var note: String {
        switch self {
        case .apple:      return "Built in. Instant, no download."
        case .kokoro:     return "⚠️ ANE, but FluidAudio's neural G2P mispronounces (\"Hi hoy\"). Use Kokoro MLX instead."
        case .kokoroMLX:  return "GPU (MLX). ~330 MB first run. Reference Misaki G2P → correct pronunciation. Text-only. ← try this for the GPU test"
        case .pocket:     return "First run downloads the model, then runs on the Neural Engine. Sounds correct."
        case .chatterbox: return "Cloning model — needs reference audio; will error without one. GPU, Mac only."
        case .qwen3:      return "First run downloads a GB+ model; runs on the GPU (MLX). Mac only."
        }
    }
}

@MainActor
final class Model: ObservableObject {
    @Published var choice: EngineChoice = .apple
    @Published var text = "Hello, this is a test of on-device text to speech."
    @Published var status = "Idle."
    @Published var busy = false
    @Published var lastDuration: Double?

    private var player: AVAudioPlayer?

    func speak() {
        guard !busy else { return }
        busy = true
        lastDuration = nil
        let choice = self.choice
        let text = self.text
        status = "Preparing \(choice.rawValue)…"

        Task {
            do {
                let engine = choice.makeEngine()
                try await engine.prepare(onProgress: { progress in
                    Task { @MainActor in self.status = "Downloading / loading… \(Int(progress * 100))%" }
                })
                await MainActor.run { self.status = "Synthesizing…" }

                let audio = try await engine.synthesize(text)
                let data = audio.wavData()

                await MainActor.run {
                    self.lastDuration = audio.duration
                    if audio.isEmpty {
                        self.status = "⚠️ Produced 0 samples."
                    } else {
                        self.status = String(format: "▶︎ Playing — %.1f s @ %d Hz (%d samples)",
                                             audio.duration, Int(audio.sampleRate), audio.samples.count)
                        #if os(iOS)
                        try? AVAudioSession.sharedInstance().setCategory(.playback)
                        try? AVAudioSession.sharedInstance().setActive(true)
                        #endif
                        self.player = try? AVAudioPlayer(data: data)
                        self.player?.play()
                    }
                    self.busy = false
                }
            } catch {
                await MainActor.run {
                    self.status = "❌ \(error.localizedDescription)"
                    self.busy = false
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var model = Model()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("swift-tts tester").font(.largeTitle.bold())

            Picker("Engine", selection: $model.choice) {
                ForEach(EngineChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)

            Text(model.choice.note)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $model.text)
                .font(.body)
                .frame(height: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            HStack(spacing: 12) {
                Button(action: model.speak) {
                    Label(model.busy ? "Working…" : "Speak", systemImage: "play.fill")
                        .frame(minWidth: 90)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.busy || model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if model.busy { ProgressView().controlSize(.small) }
                Spacer()
            }

            Text(model.status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .frame(width: 540, height: 360)
    }
}
