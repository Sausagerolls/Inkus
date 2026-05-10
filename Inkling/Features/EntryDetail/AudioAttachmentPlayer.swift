import SwiftUI
import AVFoundation

/// Tiny inline player for an `.audio` Attachment. Loads the M4A from the
/// Attachment's Data blob via a temp file (AVAudioPlayer needs a file URL),
/// shows a play/pause control, elapsed-of-total readout, and a thin progress
/// strip. Self-contained — no global player.
@MainActor
struct AudioAttachmentPlayer: View {
    let attachment: Attachment

    @State private var player: AVAudioPlayer?
    @State private var isPlaying: Bool = false
    @State private var progress: Double = 0
    @State private var duration: TimeInterval = 0
    @State private var ticker: Timer?

    var body: some View {
        HStack(spacing: Spacing.m) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.inkAccent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause audio" : "Play audio")

            VStack(alignment: .leading, spacing: Spacing.xs) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Color.inkAccent)
                HStack {
                    Text(formatTime(progress * duration))
                    Spacer()
                    Text(formatTime(duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.inkSecondary.opacity(0.6))
        )
        .onAppear { prepare() }
        .onDisappear { teardown() }
    }

    // MARK: Lifecycle

    private func prepare() {
        guard let data = attachment.data, !data.isEmpty else { return }
        // AVAudioPlayer can read M4A from Data directly via init(data:).
        player = try? AVAudioPlayer(data: data)
        player?.prepareToPlay()
        duration = player?.duration ?? 0
    }

    private func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            ticker?.invalidate()
        } else {
            player.play()
            isPlaying = true
            ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                Task { @MainActor in
                    if let player = self.player {
                        if player.duration > 0 {
                            self.progress = player.currentTime / player.duration
                        }
                        if !player.isPlaying {
                            self.isPlaying = false
                            self.ticker?.invalidate()
                        }
                    }
                }
            }
        }
    }

    private func teardown() {
        ticker?.invalidate()
        player?.stop()
        isPlaying = false
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
