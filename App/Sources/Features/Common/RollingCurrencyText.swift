import SwiftUI

struct RollingCurrencyText: View {
    @Environment(AppTheme.self) private var theme

    let amount: Double
    let mode: EarningsDisplayMode

    var body: some View {
        Text(amount, format: .currency(code: "USD"))
            .font(.system(size: 72, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .kerning(-1.6)
            .foregroundStyle(theme.accent(for: mode))
            .contentTransition(.numericText(value: amount))
            .shadow(color: theme.accent(for: mode).opacity(0.35), radius: 22, y: 0)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .animation(.smooth(duration: 0.5), value: amount)
    }
}
