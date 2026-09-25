import SwiftUI
import AVFoundation

/// Messages-style recorder for a journal entry.
/// Hold the mic to record, slide up to lock, slide left to cancel.
/// Letting go shows the review bar: play, "+ 0:07" to keep going, send to add it, X to throw it away.
struct VoiceRecorderBar<Tools: View, Leading: View>: View {
    @ObservedObject var voice: VoiceNoteService
    var onSend: () async -> Void
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var tools: () -> Tools

    @State private var locked = false
    @State private var cancelled = false
    @State private var drag: CGSize = .zero
    @State private var holding = false
    @State private var player: AVAudioPlayer?
    @State private var pressStart: Date?
    @State private var pressGeneration = 0
    @State private var startTask: Task<Void, Never>?
    private let minimumHold: TimeInterval = 0.45

    private let lockDistance: CGFloat = 70
    private let cancelDistance: CGFloat = 110

    var body: some View {
        VStack(spacing: 8) {
            if holding && !locked {
                ZStack(alignment: .trailing) {
                    Text(voice.isRecording ? "Slide up to lock · Slide left to cancel" : "Hold to record audio")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    lockHint
                }
                .transition(.opacity)
            }
            HStack(spacing: 10) {
                leading()
                ZStack(alignment: .trailing) {
                    Group {
                        if voice.isActive { recorder } else { tools() }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .glassEffect(.regular, in: .capsule)
                    .accessibilityIdentifier("audioHoldBar")
                    if !voice.isActive || holding { micHitArea }
                }
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 0)
        .animation(.snappy(duration: 0.2), value: voice.isActive)
        .animation(.snappy(duration: 0.2), value: voice.isReviewing)
    }

    private var lockHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock").font(.scaled(size: 15, weight: .medium))
            Image(systemName: "chevron.up").font(.scaled(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
        .frame(width: 40, height: 76)
        .glassEffect(.regular, in: .capsule)
        .offset(y: min(0, drag.height) * 0.4)
    }

    private var recorder: some View {
        HStack(spacing: 8) {
            Button { player?.stop(); voice.cancel(); locked = false } label: {
                Image(systemName: "xmark").font(.scaled(size: 16, weight: .medium))
                    .foregroundStyle(.secondary).frame(width: 32, height: 42)
            }
            .buttonStyle(.plain).accessibilityLabel("Delete recording")
            if voice.isReviewing {
                Button(action: play) {
                    Image(systemName: "play.fill").font(.scaled(size: 13)).foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }.buttonStyle(.plain).accessibilityLabel("Play recording")
            }
            LiveBars(levels: voice.levels, color: voice.isReviewing ? Color(.systemGray) : .red)
            if voice.isReviewing {
                Button { player?.stop(); voice.resume(); locked = true } label: {
                    Label(time, systemImage: "plus").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }.buttonStyle(.plain).accessibilityLabel("Keep recording")
                Button { player?.stop(); locked = false; Task { await onSend() } } label: {
                    Image(systemName: "arrow.up").font(.scaled(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 32, height: 32).background(Theme.accent, in: .circle)
                }.buttonStyle(.plain).accessibilityLabel("Add voice note").accessibilityIdentifier("voiceSend")
            } else {
                Text(time).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                Button { voice.pause(); locked = false } label: {
                    Image(systemName: "stop.fill").font(.scaled(size: 12)).foregroundStyle(.red)
                        .frame(width: 32, height: 32).background(.red.opacity(0.15), in: .circle)
                }.buttonStyle(.plain).accessibilityLabel("Stop recording")
            }
        }
        .padding(.leading, 10).padding(.trailing, 8)
        .frame(height: 48)
        .offset(x: holding && !locked ? min(0, drag.width) * 0.5 : 0)
    }

    /// The mic stays under the finger for the whole hold, even while the bar changes around it.
    private var micHitArea: some View {
        Image(systemName: "mic.fill")
            .font(.body.weight(.medium))
            .foregroundStyle(Theme.accent)
            .frame(width: 44, height: 48)
            .contentShape(.rect)
            .allowsHitTesting(!voice.isActive || holding)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !holding {
                            holding = true; locked = false; cancelled = false; pressStart = .now
                            pressGeneration += 1
                            let generation = pressGeneration
                            startTask?.cancel()
                            startTask = Task { @MainActor in
                                try? await Task.sleep(for: .seconds(minimumHold))
                                guard !Task.isCancelled, holding, !cancelled, pressGeneration == generation else { return }
                                // Permission may take longer than the hold. If the finger lifts
                                // during that prompt, discard any recorder that starts afterward.
                                do { try await voice.start() } catch { return }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                if !holding && !locked { voice.cancel() }
                            }
                        }
                        guard !locked, !cancelled else { return }
                        drag = value.translation
                        if value.translation.height < -lockDistance {
                            // Lock only after the minimum hold has actually been reached.
                            if voice.isRecording { locked = true; drag = .zero; UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                        } else if value.translation.width < -cancelDistance {
                            cancelled = true; drag = .zero; pressGeneration += 1
                            startTask?.cancel(); voice.cancel()
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        }
                    }
                    .onEnded { _ in
                        holding = false; drag = .zero
                        let quick = pressStart.map { Date.now.timeIntervalSince($0) < minimumHold } ?? true
                        if quick && !locked && !cancelled {
                            pressGeneration += 1; startTask?.cancel(); voice.cancel()
                        } else if !locked && !cancelled {
                            // A real press can still race microphone permission; do not keep a
                            // late-started recorder once the finger is gone.
                            pressGeneration += 1; startTask?.cancel()
                            if voice.isRecording { voice.pause() }
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Voice memo")
            .accessibilityHint("Touch and hold to record. Slide up to lock, slide left to cancel.")
            .accessibilityAction { locked = true; Task { try? await voice.start() } }
            .accessibilityIdentifier("voiceMic")
    }

    private var time: String { Duration.seconds(voice.elapsed).formatted(.time(pattern: .minuteSecond)) }

    private func play() {
        player = voice.currentURL.flatMap { try? AVAudioPlayer(contentsOf: $0) }
        player?.play()
    }
}

/// Bars that grow from the right as you speak, like Messages.
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
