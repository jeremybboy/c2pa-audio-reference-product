import SwiftUI

struct WaveformView: View {
    let samples: [Float]
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color.lgWaveformBackground)

                if samples.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "waveform")
                            .font(.system(size: 34, weight: .light))
                        Text("Your generated loop will appear here")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(Color.lgMuted.opacity(0.72))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    waveformPath(in: geometry.size)
                        .stroke(
                            LinearGradient(
                                colors: [.lgPurpleBright, .lgPurple],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            style: StrokeStyle(lineWidth: 1.35, lineCap: .round)
                        )
                        .padding(.vertical, 12)

                    Rectangle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 2)
                        .offset(x: max(0, min(geometry.size.width - 2, geometry.size.width * progress)))
                        .shadow(color: .white.opacity(0.4), radius: 4)
                }
            }
        }
    }

    private func waveformPath(in size: CGSize) -> Path {
        var path = Path()
        guard samples.count > 1 else { return path }
        let midpoint = size.height / 2
        let usableHeight = size.height * 0.43
        let spacing = size.width / CGFloat(samples.count - 1)

        for (index, sample) in samples.enumerated() {
            let x = CGFloat(index) * spacing
            let amplitude = max(1.5, CGFloat(sample) * usableHeight)
            path.move(to: CGPoint(x: x, y: midpoint - amplitude))
            path.addLine(to: CGPoint(x: x, y: midpoint + amplitude))
        }
        return path
    }
}
