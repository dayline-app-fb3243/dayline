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
    @State private var readyToSend = false
    @State private var sending = false
    @State private var startTask: Task<Void, Never>?
    @State private var recordingUI = false
    @State private var player: AVAudioPlayer?
    private let minimumHold: TimeInterval = 0.45
    private let cancelDistance: CGFloat = 75

    var body: some View {
        HStack(spacing: 10) {
            if readyToSend {
                Button {
                    player?.stop(); player = nil
                    voice.cancel(); readyToSend = false; recordingUI = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.medium)).foregroundStyle(.primary)
                        .frame(width: 48, height: 48)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .accessibilityLabel("Discard voice note")
                .accessibilityIdentifier("voiceCancel")
            } else if !recordingUI {
                leading()
            }
            ZStack(alignment: .trailing) {
                if readyToSend || recordingUI {
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
                if !readyToSend && !recordingUI && !hintVisible {
                    Button {
                        hintVisible = true
                        hintTask?.cancel()
                        hintTask = Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1.5))
                            if !Task.isCancelled { hintVisible = false }
                        }
                    } label: {
                        Circle().fill(Color.clear)
                        .frame(width: 58, height: 58)
                        .overlay {
                            Image(systemName: "mic.fill")
                                .font(.scaled(size: 19, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(width: 48, height: 48)
                                .glassEffect(.regular.interactive(), in: .circle)
                                .allowsHitTesting(false)
                        }
                        .contentShape(Circle())
                    }
                        .buttonStyle(.plain)
                        .transition(.scale(scale: 0.2, anchor: .trailing).combined(with: .opacity))
                        .gesture(LongPressGesture(minimumDuration: minimumHold, maximumDistance: cancelDistance)
                            .onEnded { _ in
                                guard !readyToSend, !recordingUI else { return }
                                hintVisible = false
                                startTask = Task { @MainActor in
                                    do { try await voice.start() } catch { return }
                                    guard voice.isRecording else { return }
                                    recordingUI = true
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                }
                            })
                        .accessibilityLabel("Voice memo")
                        .accessibilityHint("Hold to record, then tap Stop to review and send")
                        .accessibilityIdentifier("voiceMic")
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .frame(height: 48, alignment: .trailing)
            .contentShape(.rect)

        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .animation(.snappy(duration: 0.25), value: recordingUI)
        .animation(.snappy(duration: 0.25), value: readyToSend)
        .animation(.snappy(duration: 0.25), value: hintVisible)
    }

    private func finishRecording() {
        voice.finishForReview()
        recordingUI = false
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
