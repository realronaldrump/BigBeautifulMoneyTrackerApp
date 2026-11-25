import SwiftUI

struct RollingCurrencyText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let amount: Double

    var body: some View {
        Text(amount, format: .currency(code: "USD"))
            .font(TimecardType.display(78, relativeTo: .largeTitle))
            .monospacedDigit().tracking(-1.1)
            .lineLimit(1).minimumScaleFactor(0.32)
            .contentTransition(reduceMotion ? .identity : .numericText(value: amount))
    }
}
