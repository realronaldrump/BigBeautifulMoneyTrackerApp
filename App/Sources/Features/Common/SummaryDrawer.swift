import SwiftUI

struct SummaryDrawer: View {
    @Environment(AppTheme.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let snapshot: DashboardSnapshot
    let mode: EarningsDisplayMode
    let compensationMode: CompensationDisplayMode
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your totals").font(TypeStyle.title3).foregroundStyle(.white)
                        Text(mode == .gross ? "Gross earnings" : "Estimated take-home")
                            .font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Earnings totals")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Hide extra details" : "Show hours, projection, and premiums")

            AdaptiveCardGrid(minimumWidth: 136) {
                MetricTile(title: "Pay period", value: payPeriodValue, accent: theme.accent(for: mode))
                MetricTile(title: "All time", value: display(snapshot.allTimeAmount(for: mode, compensationMode: compensationMode)), accent: theme.accent(for: mode))
                if isExpanded {
                    MetricTile(title: "Hours this period", value: payPeriodMetric(snapshot.payPeriodHours.formatted(.number.precision(.fractionLength(1))) + " hrs"), accent: theme.accent(for: mode))
                    MetricTile(title: "Projected paycheck", value: projectedValue, accent: theme.accent(for: mode))
                    MetricTile(title: "Night premium · gross", value: payPeriodMetric(display(snapshot.payPeriodNightPremium)), accent: theme.accent(for: mode))
                    MetricTile(title: "Lifetime hours", value: snapshot.allTimeHours.formatted(.number.precision(.fractionLength(1))) + " hrs", accent: theme.accent(for: mode))
                }
            }
            if isExpanded {
                Text(snapshot.payPeriodAggregation == .unified ? snapshot.projectedConfidenceLabel : "Pay periods differ between jobs. Open Summary for each job’s totals.")
                    .font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .glassCard(cornerRadius: CornerRadius.cardLarge, accent: theme.accent(for: mode), hasShadow: false)
    }

    private func display(_ amount: Double) -> String { amount.formatted(.currency(code: "USD")) }
    private var payPeriodValue: String { payPeriodMetric(display(snapshot.payPeriodAmount(for: mode, compensationMode: compensationMode))) }
    private var projectedValue: String {
        payPeriodMetric(display(snapshot.projectedPaycheckAmount(for: mode, compensationMode: compensationMode)))
    }
    private func payPeriodMetric(_ value: String) -> String {
        snapshot.payPeriodAggregation == .unified ? value : "Varies by job"
    }
}
