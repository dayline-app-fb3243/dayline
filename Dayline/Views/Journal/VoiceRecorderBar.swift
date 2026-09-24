import SwiftUI
import AVFoundation
import AudioToolbox

/// Messages-style recorder for a journal entry (design: hold-3 #2).
/// Hold the mic to record, slide up to lock, slide left to cancel.
/// Letting go shows the review bar: play, "+ 0:07" to keep going, send to add it, X to throw it away.
struct VoiceRecorderBar<Tools: View>: View {
    @ObservedObject var voice: VoiceNoteService
    var onSend: () async -> Void
    @ViewBuilder var tools: () -> Tools

    @State private var locked = false
    @State private var cancelled = false
    @State private var drag: CGSize = .zero
    @State private var holding = false
    @State private var player: AVAudioPlayer?
    @State private var pressStart: Date?
    @State private var showTapHint = false

    private let lockDistance: CGFloat = 70
    private let cancelDistance: CGFloat = 110

    var body: some View {
        VStack(spacing: 8) {
            if voice.isRecording && holding && !locked {
                ZStack(alignment: .trailing) {
                    Text("Slide up to lock · Slide left to cancel")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    lockHint
                }
                .transition(.opacity)
            }
            ZStack(alignment: .trailing) {
                if showTapHint && !voice.isActive { tapHint } else if voice.isActive { recorder } else { tools() }
                micHitArea
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 6)
        .animation(.snappy(duration: 0.2), value: voice.isActive)
        .animation(.snappy(duration: 0.2), value: voice.isReviewing)
    }

    // MARK: pieces

    /// Quick tap on the mic (like Messages): a short hint in the bar instead of recording.
    private var tapHint: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Text("Tap and hold to record").font(.body).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 18).frame(height: 48)
                    .glassEffect(.regular, in: .capsule)
                Image(systemName: "mic.fill").font(.system(size: 20, weight: .regular)).foregroundStyle(Theme.accent)
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tapHoldHint")
    }

    private var lockHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock").font(.system(size: 15, weight: .medium))
            Image(systemName: "chevron.up").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
        .frame(width: 40, height: 76)
        .glassEffect(.regular, in: .capsule)
        .offset(y: min(0, drag.height) * 0.4)
    }

    private var recorder: some View {
        HStack(spacing: 10) {
            Button { player?.stop(); voice.cancel(); locked = false } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .medium)).foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Delete recording")

            HStack(spacing: 10) {
                if voice.isReviewing {
                    Button(action: play) {
                        Image(systemName: "play.fill").font(.system(size: 13)).foregroundStyle(.secondary)
                            .frame(width: 30, height: 30).background(Color(.tertiarySystemFill), in: .circle)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Play recording")
                }
                LiveBars(levels: voice.levels, color: voice.isReviewing ? Color(.systemGray) : .red)
                if voice.isReviewing {
                    Button { player?.stop(); voice.resume(); locked = true } label: {
                        Label(time, systemImage: "plus").font(.subheadline).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10).frame(height: 30)
                            .background(Color(.tertiarySystemFill), in: .capsule)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Keep recording")
                    Button { player?.stop(); locked = false; Task { await onSend() } } label: {
                        Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 34, height: 34).background(Theme.accent, in: .circle)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Add voice note").accessibilityIdentifier("voiceSend")
                } else {
                    Text(time).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                    Button { voice.pause(); locked = false } label: {
                        Image(systemName: "stop.fill").font(.system(size: 13)).foregroundStyle(.red)
                            .frame(width: 34, height: 34).background(.red.opacity(0.18), in: .circle)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Stop recording")
                }
            }
            .padding(.leading, 16).padding(.trailing, 7)
            .frame(height: 48)
            .glassEffect(.regular, in: .capsule)
            .offset(x: holding && !locked ? min(0, drag.width) * 0.5 : 0)
        }
    }

    /// The mic stays under the finger for the whole hold, even while the bar changes around it.
    private var micHitArea: some View {
        Color.clear
            .frame(width: 88, height: 52)
            .contentShape(.rect)
            .allowsHitTesting(!voice.isActive || holding)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !holding {
                            holding = true; locked = false; cancelled = false; pressStart = .now; showTapHint = false
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            Task { try? await voice.start() }
                        }
                        guard !locked, !cancelled else { return }
                        drag = value.translation
                        if value.translation.height < -lockDistance {
                            locked = true; drag = .zero
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } else if value.translation.width < -cancelDistance {
                            cancelled = true; drag = .zero
                            voice.cancel()
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        }
                    }
                    .onEnded { _ in
                        holding = false; drag = .zero
                        let quick = pressStart.map { Date.now.timeIntervalSince($0) < 0.35 } ?? false
                        if quick && !locked && !cancelled {
                            // Too short to be a recording: throw it away and show the hint, with a tick + haptic.
                            Task { try? await Task.sleep(for: .milliseconds(150)); voice.cancel() }
                            AudioServicesPlaySystemSound(1104)
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            withAnimation(.snappy(duration: 0.2)) { showTapHint = true }
                            Task { try? await Task.sleep(for: .seconds(2)); withAnimation(.snappy(duration: 0.25)) { showTapHint = false } }
                        } else if !locked && !cancelled {
                            // Give start() a moment if the hold was very short.
                            Task { try? await Task.sleep(for: .milliseconds(150)); voice.pause() }
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Voice note")
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
