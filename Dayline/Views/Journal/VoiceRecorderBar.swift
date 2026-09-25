import SwiftUI
import AVFoundation

/// The microphone starts recording after a deliberate hold. Release attaches the note;
/// sliding away cancels. The recorder grows from the microphone only while recording.
struct VoiceRecorderBar<Tools: View, Leading: View>: View {
    @ObservedObject var voice: VoiceNoteService
    var onSend: () async -> Void
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var tools: () -> Tools

    @State private var holding = false
    @State private var cancelled = false
    @State private var pressStarted: Date?
    @State private var startTask: Task<Void, Never>?
    @State private var pressGeneration = 0
    private let minimumHold: TimeInterval = 0.45
    private let cancelDistance: CGFloat = 75

    var body: some View {
        VStack(spacing: 8) {
            if holding {
                Text(voice.isRecording ? "Slide away to cancel" : "Hold to record audio")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
            HStack(spacing: 10) {
                leading()
                ZStack(alignment: .trailing) {
                    Group {
                        if voice.isRecording {
                            HStack(spacing: 8) {
                                Circle().fill(.red).frame(width: 8, height: 8)
                                LiveBars(levels: voice.levels, color: .red)
                                Text(Duration.seconds(voice.elapsed).formatted(.time(pattern: .minuteSecond)))
                                    .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                                Spacer(minLength: 44)
                            }
                            .padding(.horizontal, 14)
                        } else { tools() }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .glassEffect(.regular, in: .capsule)
                    .accessibilityIdentifier("audioHoldBar")
                    Image(systemName: "mic.fill")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 44, height: 48)
                        .contentShape(.rect)
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !holding {
                                    holding = true; cancelled = false; pressStarted = .now
                                    pressGeneration += 1
                                    let generation = pressGeneration
                                    startTask?.cancel()
                                    startTask = Task { @MainActor in
                                        try? await Task.sleep(for: .seconds(minimumHold))
                                        guard !Task.isCancelled, holding, !cancelled, pressGeneration == generation else { return }
                                        do { try await voice.start() } catch { return }
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        if !holding || cancelled { voice.cancel() }
                                    }
                                }
                                if abs(value.translation.width) > cancelDistance || abs(value.translation.height) > cancelDistance {
                                    cancelled = true
                                    startTask?.cancel()
                                    voice.cancel()
                                }
                            }
                            .onEnded { _ in
                                holding = false
                                pressGeneration += 1
                                startTask?.cancel()
                                let longEnough = pressStarted.map { Date.now.timeIntervalSince($0) >= minimumHold } ?? false
                                if !longEnough || cancelled { voice.cancel() }
                                else if voice.isRecording { Task { await onSend() } }
                                // If mic permission arrives after release, the start task cancels it.
                            })
                        .accessibilityLabel("Voice memo")
                        .accessibilityHint("Hold to record, release to attach, slide away to cancel")
                        .accessibilityIdentifier("voiceMic")
                }
            }
        }
        .padding(.horizontal, 16)
        .animation(.snappy(duration: 0.2), value: voice.isRecording)
    }
}

struct LiveBars: View {
    let levels: [Float]
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let count = max(1, Int(geo.size.width / 4.5))
            let shown = Array(levels.suffix(count))
            HStack(spacing: 2) {
                Spacer(minLength: 0)
                ForEach(Array(shown.enumerated()), id: \.offset) { _, l in
                    Capsule().fill(color).frame(width: 2.5, height: max(3, CGFloat(l) * 22))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 24)
    }
}
