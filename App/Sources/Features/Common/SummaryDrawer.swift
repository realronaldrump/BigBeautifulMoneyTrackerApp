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
                        Text("Earnings details").font(TypeStyle.title3).foregroundStyle(TimecardColor.ink)
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

            if isExpanded {
                AdaptiveCardGrid(minimumWidth: 136) {
                    MetricTile(title: "Pay period", value: payPeriodValue, accent: theme.accent(for: mode))
                    MetricTile(title: "All time", value: display(snapshot.allTimeAmount(for: mode, compensationMode: compensationMode)), accent: theme.accent(for: mode))
                    if !snapshot.salaryJobs.isEmpty {
                        MetricTile(title: "Salary work hours", value: snapshot.salaryJobs.reduce(0) { $0 + $1.loggedHours }.formatted(.number.precision(.fractionLength(1))) + " hrs logged", accent: theme.accent(for: mode))
                    }
                    if snapshot.salaryJobs.isEmpty || snapshot.payPeriodHours > 0 {
                        MetricTile(title: "Hourly shift hours", value: payPeriodMetric(snapshot.payPeriodHours.formatted(.number.precision(.fractionLength(1))) + " hrs"), accent: theme.accent(for: mode))
                    }
                    MetricTile(title: "Projected paycheck", value: projectedValue, accent: theme.accent(for: mode))
                    if snapshot.payPeriodNightPremium > 0 {
                        MetricTile(title: "Night premium · gross", value: payPeriodMetric(display(snapshot.payPeriodNightPremium)), accent: theme.accent(for: mode))
                    }
                    if snapshot.salaryJobs.isEmpty || snapshot.allTimeHours > 0 {
                        MetricTile(title: "Lifetime hourly hours", value: snapshot.allTimeHours.formatted(.number.precision(.fractionLength(1))) + " hrs", accent: theme.accent(for: mode))
                    }
                }
                Text(snapshot.payPeriodAggregation == .unified ? snapshot.projectedConfidenceLabel : "Pay periods differ between jobs. Open Summary for each job’s totals.")
                    .font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .ruledSection()
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
