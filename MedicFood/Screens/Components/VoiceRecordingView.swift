import SwiftUI

/// Record / stop / play / delete / record again, with the running duration.
struct VoiceRecordingView: View {
    let voice: VoiceController
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: voice.isRecording ? "waveform" : "mic")
                    .foregroundStyle(voice.isRecording ? Theme.Colors.missed : Theme.Colors.primary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(VoiceController.format(voice.duration))
                    .font(Theme.Typography.numeral(17, weight: .semibold))
                    .monospacedDigit()
                    .accessibilityLabel("Duration \(VoiceController.format(voice.duration))")
            }

            HStack(spacing: 10) {
                if voice.isRecording {
                    control("Stop", "stop.fill", tint: Theme.Colors.missed) { voice.stopRecording() }
                } else {
                    control(voice.hasRecording ? "Record again" : "Record", "mic.fill", tint: Theme.Colors.primary) {
                        Task { await voice.startRecording() }
                    }
                    if voice.hasRecording {
                        control(voice.isPlaying ? "Pause" : "Play", voice.isPlaying ? "pause.fill" : "play.fill", tint: Theme.Colors.brand) {
                            voice.togglePlayback()
                        }
                        control("Delete", "trash", tint: Theme.Colors.missed) { voice.delete() }
                    }
                }
            }

            if voice.permissionDenied {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Microphone access is required to record medication instructions.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.missed)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
                }
            }

            if let message = voice.errorMessage {
                Text(message).font(.footnote).foregroundStyle(Theme.Colors.missed)
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        if voice.isRecording { return "Recording…" }
        return voice.hasRecording ? "Voice instruction" : "No recording yet"
    }

    private func control(_ label: String, _ symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 38)
                .foregroundStyle(tint)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.borderless)
    }
}
