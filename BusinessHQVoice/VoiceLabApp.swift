
import SwiftUI
import AVFoundation
import FluidAudio

@main
struct BusinessHQVoiceApp: App {
    var body: some Scene {
        WindowGroup {
            VoiceLabView()
        }
    }
}

enum Speaker: String, CaseIterable, Identifiable {
    case chatgpt = "ChatGPT"
    case claude = "Claude"
    case grok = "Grok"

    var id: String { rawValue }

    // Pocket TTS stock voice presets.
    // These are not clones of WevoLabs samples.
    var voiceID: String {
        switch self {
        case .chatgpt:
            return "michael"
        case .claude:
            return "alba"
        case .grok:
            return "stuart_bell"
        }
    }
}

@MainActor
final class VoiceLabState: ObservableObject {
    @Published var input =
        "Hey boss. Welcome back to Business HQ."

    @Published var speaker: Speaker = .chatgpt
    @Published var running = false

    @Published var log =
        "Ready. No network calls except optional model download.\n"

    private var model: PocketTtsManager?
    private var player: AVAudioPlayer?

    private func record(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        log +=
            "[\(formatter.string(from: Date()))] \(message)\n"
    }

    func run() async {
        guard !running else { return }

        let utterance = input.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !utterance.isEmpty &&
              utterance.count <= 350 else {
            record("ERROR: Enter 1–350 characters.")
            return
        }

        running = true
        defer { running = false }

        record(
            "Start speaker=\(speaker.rawValue), " +
            "preset=\(speaker.voiceID), " +
            "chars=\(utterance.count)"
        )

        do {
            try AVAudioSession.sharedInstance()
                .setCategory(.playback, mode: .default)

            try AVAudioSession.sharedInstance()
                .setActive(true)

            if model == nil {
                record(
                    "Initializing Pocket TTS. " +
                    "Initial model download needs Wi-Fi " +
                    "and may be large."
                )

                let before = Date()
                let newModel = PocketTtsManager()

                try await newModel.initialize()
                model = newModel

                record(
                    String(
                        format: "Model ready in %.2f seconds",
                        Date().timeIntervalSince(before)
                    )
                )
            }

            guard let model else { return }

            record("Generating fresh speech on device...")

            let start = Date()

            let wav = try await model.synthesize(
                text: utterance,
                voice: speaker.voiceID
            )

            let duration =
                Date().timeIntervalSince(start)

            record(
                String(
                    format: "Generated %d bytes in %.2f seconds",
                    wav.count,
                    duration
                )
            )

            player?.stop()
            player = try AVAudioPlayer(data: wav)
            player?.prepareToPlay()

            guard player?.play() == true else {
                throw VoiceLabError.playback
            }

            record(
                String(
                    format: "PLAYING, %.2f seconds of audio",
                    player?.duration ?? 0
                )
            )

        } catch {
            record(
                "ERROR \(type(of: error)): " +
                "\(error.localizedDescription)"
            )
        }
    }

    func stop() {
        player?.stop()
        record("Stopped.")
    }
}

enum VoiceLabError: LocalizedError {
    case playback

    var errorDescription: String? {
        "Audio player did not start"
    }
}

struct VoiceLabView: View {
    @StateObject private var state = VoiceLabState()

    var body: some View {
        NavigationStack {
            Form {
                Section("Generate NEW speech") {
                    Picker(
                        "Voice",
                        selection: $state.speaker
                    ) {
                        ForEach(Speaker.allCases) { voice in
                            Text(voice.rawValue).tag(voice)
                        }
                    }

                    TextEditor(text: $state.input)
                        .frame(minHeight: 95)
                        .accessibilityLabel(
                            "Speech test text"
                        )

                    Button(
                        state.running
                        ? "Generating..."
                        : "Generate & Play"
                    ) {
                        Task {
                            await state.run()
                        }
                    }
                    .disabled(state.running)

                    Button("Stop playback") {
                        state.stop()
                    }
                }

                Section("Diagnostic log") {
                    Text(state.log)
                        .font(
                            .system(
                                .caption,
                                design: .monospaced
                            )
                        )
                        .textSelection(.enabled)

                    ShareLink(
                        "Share test log",
                        item: state.log
                    )
                }

                Section("Safety") {
                    Text(
                        "LOCAL TEST ONLY: no Supabase access, " +
                        "no OpenAI/Anthropic/xAI API requests, " +
                        "no business action controls, " +
                        "no voice cloning."
                    )
                    .font(.footnote)
                }
            }
            .navigationTitle("HQ Voice Lab")
            .tint(.orange)
        }
    }
}
