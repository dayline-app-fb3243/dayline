import SwiftUI
import AVFoundation

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
    @State private var pressGeneration = 0
    @State private var startTask: Task<Void, Never>?
    private let minimumHold: TimeInterval = 0.45
    @State private var showTapHint = false
    @State private var hintToken = 0

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

    /// Quick tap previews. None of these start or save audio.
    private var hintStyle: Int {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-voiceHint"), i + 1 < a.count else { return 1 }
        return Int(a[i + 1]) ?? 1
    }
    private var tapHint: some View {
        Group {
            switch hintStyle {
            case 2:
                HStack(spacing: 8) {
                    Image(systemName: "hand.point.up.left").foregroundStyle(Theme.accent)
                    Text("Hold the mic to record").foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "mic.fill").foregroundStyle(Theme.accent)
                }
                .font(.subheadline).padding(.horizontal, 16).frame(height: 48)
                .background(Color(.secondarySystemGroupedBackground), in: .capsule)
            case 3:
                HStack {
                    Spacer()
                    Text("Hold to record").font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "mic.fill").foregroundStyle(Theme.accent)
                        .frame(width: 48, height: 48).glassEffect(.regular, in: .circle)
                }
            case 4:
                HStack {
                    Spacer()
                    Label("Hold for voice note", systemImage: "waveform")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .padding(.horizontal, 14).frame(height: 42)
                        .background(Color(.secondarySystemGroupedBackground), in: .capsule)
                }
            default:
                HStack {
                    Spacer()
                    Image(systemName: "mic.fill").font(.title3).foregroundStyle(Theme.accent)
                        .frame(width: 48, height: 48).glassEffect(.regular, in: .circle)
                }
            }
        }
        .frame(height: 48).transition(.opacity)
        .accessibilityIdentifier("tapHoldHint")
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
        HStack(spacing: 10) {
            Button { player?.stop(); voice.cancel(); locked = false } label: {
                Image(systemName: "xmark").font(.scaled(size: 17, weight: .medium)).foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Delete recording")

            HStack(spacing: 10) {
                if voice.isReviewing {
                    Button(action: play) {
                        Image(systemName: "play.fill").font(.scaled(size: 13)).foregroundStyle(.secondary)
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
                        Image(systemName: "arrow.up").font(.scaled(size: 16, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 34, height: 34).background(Theme.accent, in: .circle)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Add voice note").accessibilityIdentifier("voiceSend")
                } else {
                    Text(time).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                    Button { voice.pause(); locked = false } label: {
                        Image(systemName: "stop.fill").font(.scaled(size: 13)).foregroundStyle(.red)
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
                            hintToken += 1; let token = hintToken
                            withAnimation(.snappy(duration: 0.2)) { showTapHint = true }
                            Task { try? await Task.sleep(for: .seconds(1.5)); if token == hintToken { withAnimation(.snappy(duration: 0.25)) { showTapHint = false } } }
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
