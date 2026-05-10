import SwiftUI
import SwiftData

struct VoiceDictationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let entry: Entry
    /// Called with the recognised text on Insert. The host inserts it into
    /// the editor body at the cursor.
    let onInsert: (String) -> Void

    @State private var coordinator = VoiceDictationCoordinator()
    @State private var isStarting = false
    @State private var showingPermissionMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcriptArea
                Divider()
                controls
                    .padding(Spacing.l)
                    .background(.regularMaterial)
            }
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { coordinator.cancel(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert", action: insertAndDismiss)
                        .fontWeight(.semibold)
                        .disabled(coordinator.currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .alert("Permission needed", isPresented: Binding(
            get: { showingPermissionMessage != nil },
            set: { if !$0 { showingPermissionMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(showingPermissionMessage ?? "")
        }
    }

    // MARK: Subviews

    private var transcriptArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                if coordinator.currentTranscript.isEmpty && !coordinator.isRecording {
                    placeholder
                } else {
                    Text(coordinator.currentTranscript.isEmpty ? "Listening…" : coordinator.currentTranscript)
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let err = coordinator.lastError {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .padding(Spacing.l)
        }
        .background(Color.inkBackground)
    }

    private var placeholder: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "mic.circle")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.inkAccent.opacity(0.7))
            Text("Tap the mic to start dictating.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Speech is recognised on your device. Audio attaches to the entry so you can listen back.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.l)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }

    private var controls: some View {
        HStack(spacing: Spacing.l) {
            elapsedLabel
            Spacer()
            micButton
            Spacer()
            if coordinator.isRecording {
                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundStyle(Color.inkAccent)
                    .symbolEffect(.variableColor.iterative)
            } else {
                Color.clear.frame(width: 24, height: 24)
            }
        }
    }

    private var elapsedLabel: some View {
        Text(formatElapsed(coordinator.elapsed))
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: 64, alignment: .leading)
    }

    private var micButton: some View {
        Button {
            Task { await toggle() }
        } label: {
            ZStack {
                Circle()
                    .fill(coordinator.isRecording ? Color.red : Color.inkAccent)
                    .frame(width: 78, height: 78)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                Image(systemName: coordinator.isRecording ? "stop.fill" : "mic.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel(coordinator.isRecording ? "Stop recording" : "Start recording")
        .disabled(isStarting)
    }

    // MARK: Actions

    private func toggle() async {
        if coordinator.isRecording {
            finishRecording()
            return
        }
        isStarting = true
        defer { isStarting = false }
        do {
            try await coordinator.start()
        } catch let dictationError as VoiceDictationCoordinator.DictationError {
            showingPermissionMessage = dictationError.errorDescription
        } catch {
            showingPermissionMessage = error.localizedDescription
        }
    }

    private func finishRecording() {
        let result = coordinator.stop()
        // Save the audio attachment immediately if the user already has audio.
        if let url = result.audioURL,
           let data = try? Data(contentsOf: url),
           !data.isEmpty {
            let attachment = Attachment(kind: .audio, filename: "voice-\(timestamp()).m4a", data: data)
            attachment.entry = entry
            modelContext.insert(attachment)
            try? modelContext.save()
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func insertAndDismiss() {
        if coordinator.isRecording { finishRecording() }
        let text = coordinator.currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            onInsert(text)
        }
        dismiss()
    }

    private func formatElapsed(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func timestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime]
        return f.string(from: .now).replacingOccurrences(of: ":", with: "-")
    }
}
