import SwiftUI

/// Пять полосок, которые прыгают от громкости голоса: видно, что микрофон слышит.
struct VoiceLevelView: View {
    let level: Float

    private let weights: [CGFloat] = [0.45, 0.75, 1, 0.75, 0.45]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(weights.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.red)
                    .frame(width: 3, height: 4 + 12 * CGFloat(level) * weights[index])
            }
        }
        .frame(height: 16)
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }
}
