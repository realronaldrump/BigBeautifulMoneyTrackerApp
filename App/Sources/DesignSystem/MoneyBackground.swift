import SwiftUI

struct MoneyBackground: View {
    @Environment(AppTheme.self) private var theme
    let mode: EarningsDisplayMode

    var body: some View {
        ZStack {
            theme.trueBlack
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    theme.trueBlack,
                    theme.secondaryPanel.opacity(0.98),
                    theme.trueBlack
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(theme.accent(for: mode).opacity(0.24))
                .frame(width: 360, height: 360)
                .blur(radius: 130)
                .offset(x: 150, y: -270)

            Circle()
                .fill(theme.complementaryAccent(for: mode).opacity(0.16))
                .frame(width: 280, height: 280)
                .blur(radius: 120)
                .offset(x: -150, y: 280)

            RoundedRectangle(cornerRadius: 130, style: .continuous)
                .fill(theme.accent(for: mode).opacity(0.10))
                .frame(width: 300, height: 230)
                .rotationEffect(.degrees(20))
                .blur(radius: 90)
                .offset(x: -150, y: 210)

            RoundedRectangle(cornerRadius: 120, style: .continuous)
                .fill(theme.takeHomeAccent.opacity(0.09))
                .frame(width: 250, height: 180)
                .rotationEffect(.degrees(-18))
                .blur(radius: 80)
                .offset(x: 150, y: 250)

            LinearGradient(
                colors: [Color.white.opacity(0.08), .clear, Color.white.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)
            .mask(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [.clear, Color.white.opacity(0.03), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}
