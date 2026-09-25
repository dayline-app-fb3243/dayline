import SwiftUI
import AVFoundation

/// The microphone starts recording after a deliberate hold. Release attaches the note;
/// sliding away cancels. The recorder grows from the microphone only while recording.
struct VoiceRecorderBar<Tools: View, Leading: View>: View {
    @ObservedObject var voice: VoiceNoteService
    var onSend: () async -> Void
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var tools: () -> Tools

    @State private var hintVisible = false
    @State private var hintTask: Task<Void, Never>?
    @State private var holding = false
    @State private var cancelled = false
    @State private var pressStarted: Date?
    @State private var startTask: Task<Void, Never>?
    @State private var pressGeneration = 0
    private let minimumHold: TimeInterval = 0.45
    private let cancelDistance: CGFloat = 75

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if voice.isRecording {
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    LiveBars(levels: voice.levels, color: .red)
                    Text(Duration.seconds(voice.elapsed).formatted(.time(pattern: .minuteSecond)))
                        .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(width: 196, height: 48)
                .glassEffect(.regular, in: .capsule)
                .accessibilityIdentifier("audioHoldBar")
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if hintVisible {
                Text("Tap and hold to talk")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).frame(height: 38)
                    .glassEffect(.regular, in: .capsule)
                    .accessibilityIdentifier("voiceHoldHint")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 10) {
                leading()
                tools()
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .glassEffect(.regular, in: .capsule)
                Image(systemName: "mic.fill")
                    .font(.scaled(size: 19, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(.circle)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !holding {
                                holding = true; cancelled = false; pressStarted = .now
                                hintTask?.cancel(); hintVisible = false
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
                            if !longEnough && !cancelled {
                                voice.cancel()
                                hintVisible = true
                                hintTask?.cancel()
                                hintTask = Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(1.5))
                                    if !Task.isCancelled { hintVisible = false }
                                }
                            } else if cancelled { voice.cancel() }
                            else if voice.isRecording { Task { await onSend() } }
                            // If mic permission arrives after release, the start task cancels it.
                        })
                    .accessibilityLabel("Voice memo")
                    .accessibilityHint("Hold to record, release to attach, slide away to cancel")
                    .accessibilityIdentifier("voiceMic")
            }
        }
        .padding(.horizontal, 16)
        .animation(.snappy(duration: 0.2), value: voice.isRecording)
        .animation(.snappy(duration: 0.2), value: hintVisible)
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
