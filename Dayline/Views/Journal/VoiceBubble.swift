import SwiftUI
import AVFoundation

/// Finished voice note, design #1: one blue bubble with play, bars and time,
/// then the words and "Transcribed" inside the same bubble.
struct VoiceBubble: View {
    let seconds: Double
    var words: String = ""
    var transcribed: Bool = false
    var failed: Bool = false
    var seed: String = ""
    var audioURL: URL? = nil

    @State private var player: AVAudioPlayer?
    @State private var progress: Double = 0
    @State private var isPlaying = false
    @State private var timer: Timer?

    private var bars: [CGFloat] {
        var h = seed.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        return (0..<30).map { _ in
            h = h &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(6 + Int((h >> 33) % 15))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: toggle) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.scaled(size: 12, weight: .bold)).foregroundStyle(Theme.accent)
                        .frame(width: 30, height: 30).background(.white, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause" : "Play voice memo")
                HStack(spacing: 2) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { i, height in
                        Capsule().fill(.white.opacity(Double(i) / Double(bars.count) < progress ? 1 : 0.45))
                            .frame(width: 3, height: height)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).clipped()
                Text(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))
                    .font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(.white)
            }
            .frame(height: 34)
            if !words.isEmpty {
                Text("\u{201C}\(words)\u{201D}").font(.subheadline).foregroundStyle(.white)
                    .padding(.top, 8).padding(.leading, 6)
            }
            if !words.isEmpty && transcribed {
                Text("Transcribed").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 4).padding(.leading, 6)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 8, bottom: 12, trailing: 14))
        .frame(maxWidth: 290, alignment: .leading)
        .background(Theme.accent, in: .rect(cornerRadius: 22, style: .continuous))
        .onDisappear { stop() }
    }

    private func toggle() {
        if let p = player, p.isPlaying { p.pause(); timer?.invalidate(); isPlaying = false; return }
        if player == nil, let url = audioURL { player = try? AVAudioPlayer(contentsOf: url) }
        guard let p = player else { return }
        p.play()
        isPlaying = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                progress = p.duration > 0 ? p.currentTime / p.duration : 0
                if !p.isPlaying { stop(keepPlayer: true) }
            }
        }
    }

    private func stop(keepPlayer: Bool = false) {
        timer?.invalidate(); timer = nil
        isPlaying = false
        if !keepPlayer { player?.stop(); player = nil }
        progress = 0
    }
}
