import SwiftUI

struct RollingCurrencyText: View {
    @Environment(AppTheme.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var fontSize = 72.0

    let amount: Double
    let mode: EarningsDisplayMode

    var body: some View {
        Text(amount, format: .currency(code: "USD"))
            .font(.system(size: min(fontSize, 108), weight: .heavy, design: .rounded))
            .monospacedDigit()
            .kerning(-1.6)
            .foregroundStyle(theme.accent(for: mode))
            .contentTransition(reduceMotion ? .identity : .numericText(value: amount))
            .shadow(color: theme.accent(for: mode).opacity(0.35), radius: 22, y: 0)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(mode.title)
            .accessibilityValue(amount.formatted(.currency(code: "USD")))
    }
}
