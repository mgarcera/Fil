import SwiftUI

struct WaveformView: View {
    let duration: TimeInterval
    var isAnimating: Bool = false
    var fillsWidth: Bool = false
    private let barCount = 24

    var body: some View {
        HStack(spacing: 10) {
            Text(formatDuration(duration))
                .font(Theme.dmMono(13))
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()

            HStack(alignment: .center, spacing: fillsWidth ? 0 : 1.5) {
                ForEach(0..<barCount, id: \.self) { index in
                    WaveformBar(isAnimating: isAnimating, index: index)
                    if fillsWidth && index < barCount - 1 {
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct CompactWaveformView: View {
    let duration: TimeInterval
    private let barCount = 12

    var body: some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(isAnimating: false, index: index)
            }
        }
    }
}

struct PlaybackWaveformView: View {
    var player: AudioPlayerViewModel
    let totalDuration: TimeInterval
    var showsPlayButton: Bool = true
    private let barCount = 24

    var body: some View {
        HStack(spacing: 10) {
            if showsPlayButton {
                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: 28, height: 28)
                        .background(Theme.activeTabBackground, in: Circle())
                }
            }

            HStack(alignment: .center, spacing: 1.5) {
                ForEach(0..<barCount, id: \.self) { index in
                    let fraction = Double(index) / Double(barCount)
                    let isPlayed = fraction < player.progress
                    WaveformBar(isAnimating: player.isPlaying && isPlayed, index: index)
                        .opacity(isPlayed ? 1.0 : 0.4)
                }
            }

            Text(timeLabel)
                .font(Theme.dmMono(11))
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()
        }
    }

    private var timeLabel: String {
        let time = player.isPlaying || player.currentTime > 0 ? player.currentTime : totalDuration
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct WaveformBar: View {
    let isAnimating: Bool
    let index: Int

    @State private var height: CGFloat = 0.3

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Theme.secondaryText)
            .frame(width: 2, height: 4 + height * 12)
            .onAppear {
                if isAnimating {
                    withAnimation(
                        .easeInOut(duration: Double.random(in: 0.3...0.7))
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.05)
                    ) {
                        height = CGFloat.random(in: 0.2...1.0)
                    }
                } else {
                    height = CGFloat.random(in: 0.2...0.8)
                }
            }
    }
}
