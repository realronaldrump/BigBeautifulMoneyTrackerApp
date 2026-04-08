import SwiftUI

struct MoneyBackground: View {
    @Environment(AppTheme.self) private var theme
    let mode: EarningsDisplayMode

    var body: some View {
        ZStack {
            theme.trueBlack
                .ignoresSafeArea()

            Circle()
                .fill(theme.accent(for: mode).opacity(0.22))
                .frame(width: 340, height: 340)
                .blur(radius: 120)
                .offset(x: 120, y: -260)

            RoundedRectangle(cornerRadius: 120)
                .fill(theme.accent(for: mode).opacity(0.12))
                .frame(width: 260, height: 220)
                .rotationEffect(.degrees(18))
                .blur(radius: 80)
                .offset(x: -140, y: 220)

            LinearGradient(
                colors: [.clear, Color.white.opacity(0.03), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}
