import SwiftUI

/// A breathing radial pulse that signals "money is being earned."
/// Place behind the hero currency text during active shifts.
struct PulseAura: View {
    let accent: Color

    @State private var phase: CGFloat = 0.5

    var body: some View {
        let ringOpacity: Double = 0.12 * Double(1 - phase)
        let glowOpacity: Double = 0.18 * Double(1 - phase * 0.6)
        let ringSize: CGFloat = 220 + phase * 80
        let glowSize: CGFloat = 280 + phase * 60
        let glowEnd: CGFloat = 140 + phase * 40

        ZStack {
            // Outer ring — slow expansion
            Circle()
                .stroke(accent.opacity(ringOpacity), lineWidth: 2)
                .frame(width: ringSize, height: ringSize)

            // Inner glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accent.opacity(glowOpacity), .clear],
                        center: .center,
                        startRadius: 30,
                        endRadius: glowEnd
                    )
                )
                .frame(width: glowSize, height: glowSize)
        }
        .blur(radius: 8)
        .allowsHitTesting(false)
    }
}
