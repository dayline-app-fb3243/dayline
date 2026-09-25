import SwiftUI
import AVFoundation

/// An iMessage-style voice control: the mic expands in place for a held recording;
/// releasing leaves a send button, and sending collapses it back to a mic.
struct VoiceRecorderBar<Tools: View, Leading: View>: View {
    @ObservedObject var voice: VoiceNoteService
    var onSend: () async -> Void
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var tools: () -> Tools

    @State private var hintVisible = false
    @State private var hintTask: Task<Void, Never>?
    @State private var holding = false
    @State private var readyToSend = false
    @State private var sending = false
    @State private var cancelled = false
    @State private var pressStarted: Date?
    @State private var startTask: Task<Void, Never>?
    @State private var pressGeneration = 0
    @State private var player: AVAudioPlayer?
    private let minimumHold: TimeInterval = 0.45
    private let cancelDistance: CGFloat = 75

    var body: some View {
        HStack(spacing: 10) {
            if readyToSend {
                Button {
                    player?.stop(); player = nil
                    voice.cancel(); readyToSend = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.medium)).foregroundStyle(.primary)
                        .frame(width: 48, height: 48)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .accessibilityLabel("Discard voice note")
                .accessibilityIdentifier("voiceCancel")
            } else if !voice.isRecording {
                leading()
            }
            ZStack(alignment: .trailing) {
                if readyToSend || voice.isRecording {
                    HStack(spacing: 8) {
                        if readyToSend {
                            Button {
                                guard let url = voice.currentURL else { return }
                                if player?.isPlaying == true { player?.stop(); player = nil }
                                else { player = try? AVAudioPlayer(contentsOf: url); player?.play() }
                            } label: {
                                Image(systemName: player?.isPlaying == true ? "pause.fill" : "play.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 34, height: 34)
                                    .background(.gray.opacity(0.12), in: .circle)
                            }
                            .accessibilityLabel("Preview voice note")
                            .accessibilityIdentifier("voicePreview")
                        }
                        LiveBars(levels: voice.levels, color: readyToSend ? Theme.accent : .red)
                        Text("\(readyToSend ? "+" : "")\(Duration.seconds(voice.elapsed).formatted(.time(pattern: .minuteSecond)))")
                            .font(.subheadline).monospacedDigit()
                            .foregroundStyle(readyToSend ? Theme.accent : .red)
                        if readyToSend {
                            Button {
                                guard !sending else { return }
                                sending = true
                                player?.stop(); player = nil
                                Task { await onSend(); readyToSend = false; sending = false }
                            } label: {
                                Image(systemName: "arrow.up").font(.headline.weight(.bold))
                                    .foregroundStyle(.white).frame(width: 38, height: 38)
                                    .background(Theme.accent, in: .circle)
                            }
                            .accessibilityLabel("Send voice note")
                            .accessibilityIdentifier("voiceSend")
                        } else {
                            Button {
                                finishRecording()
                            } label: {
                                Image(systemName: "stop.fill").font(.subheadline)
                                    .foregroundStyle(.red).frame(width: 38, height: 38)
                                    .background(.red.opacity(0.12), in: .circle)
                            }
                            .accessibilityLabel("Stop recording")
                            .accessibilityIdentifier("voiceStop")
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .glassEffect(.regular, in: .capsule)
                    .accessibilityIdentifier(readyToSend ? "audioReadyBar" : "audioHoldBar")
                    .transition(.scale(scale: 0.2, anchor: .trailing).combined(with: .opacity))
                } else if hintVisible {
                    Text("Tap and hold to talk")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.horizontal, 13)
                        .frame(height: 48)
                        .glassEffect(.regular, in: .capsule)
                        .accessibilityIdentifier("voiceHoldHint")
                        .transition(.scale(scale: 0.2, anchor: .trailing).combined(with: .opacity))
                }
                if !readyToSend && !voice.isRecording && !hintVisible {
                    Image(systemName: "mic.fill")
                        .font(.scaled(size: 19, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 48, height: 48)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .transition(.scale(scale: 0.2, anchor: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .frame(height: 48, alignment: .trailing)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !readyToSend, !voice.isRecording else { return }
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
                    guard !readyToSend else { return }
                    if voice.isRecording { holding = false; return }
                    holding = false; pressGeneration += 1; startTask?.cancel()
                    let longEnough = pressStarted.map { Date.now.timeIntervalSince($0) >= minimumHold } ?? false
                    if !longEnough && !cancelled {
                        voice.cancel(); hintVisible = true
                        hintTask?.cancel()
                        hintTask = Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1.5))
                            if !Task.isCancelled { hintVisible = false }
                        }
                    } else if cancelled { voice.cancel() }
                    else if voice.isRecording { holding = false }
                    // If microphone permission arrives after release, the start task cancels it.
                })
            .accessibilityLabel("Voice memo")
            .accessibilityHint("Hold to record, release to review and send, slide away to cancel")
            .accessibilityIdentifier("voiceMic")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .animation(.snappy(duration: 0.25), value: voice.isRecording)
        .animation(.snappy(duration: 0.25), value: readyToSend)
        .animation(.snappy(duration: 0.25), value: hintVisible)
    }

    private func finishRecording() {
        voice.finishForReview()
        readyToSend = true
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
