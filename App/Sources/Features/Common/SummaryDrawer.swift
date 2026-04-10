import SwiftUI

struct SummaryDrawer: View {
    @Environment(AppTheme.self) private var theme

    let snapshot: DashboardSnapshot
    let mode: EarningsDisplayMode

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 46, height: 5)
                .padding(.top, 10)

            VStack(spacing: Spacing.md) {
                HStack {
                    Text("Beneath The Ticker")
                        .font(TypeStyle.title3)
                        .foregroundStyle(Color.white)
                    Spacer()
                    Text(isExpanded ? "Hide" : "Reveal")
                        .font(TypeStyle.caption)
                        .foregroundStyle(theme.secondaryText)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricTile(
                        title: "Pay Period",
                        value: payPeriodValue,
                        accent: theme.accent(for: mode)
                    )
                    MetricTile(
                        title: "All Time",
                        value: display(snapshot.allTimeGross, takeHome: snapshot.allTimeTakeHome),
                        accent: theme.accent(for: mode)
                    )

                    if isExpanded {
                        MetricTile(
                            title: "Hours This Cycle",
                            value: payPeriodMetric(
                                snapshot.payPeriodHours.formatted(.number.precision(.fractionLength(1))) + " hrs"
                            ),
                            accent: theme.accent(for: mode)
                        )
                        MetricTile(
                            title: "Projected Check",
                            value: projectedValue,
                            accent: theme.accent(for: mode)
                        )
                        MetricTile(
                            title: "Night Premium",
                            value: payPeriodMetric(snapshot.payPeriodNightPremium.formatted(.currency(code: "USD"))),
                            accent: theme.accent(for: mode)
                        )
                        MetricTile(
                            title: "Lifetime Hours",
                            value: snapshot.allTimeHours.formatted(.number.precision(.fractionLength(1))) + " hrs",
                            accent: theme.accent(for: mode)
                        )
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .glassCard(cornerRadius: CornerRadius.cardLarge, accent: theme.accent(for: mode))
        .onTapGesture {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                isExpanded.toggle()
            }
        }
    }

    private func display(_ gross: Double, takeHome: Double) -> String {
        let amount = mode == .gross ? gross : takeHome
        return amount.formatted(.currency(code: "USD"))
    }

    private var payPeriodValue: String {
        payPeriodMetric(display(snapshot.payPeriodGross, takeHome: snapshot.payPeriodTakeHome))
    }

    private var projectedValue: String {
        guard snapshot.payPeriodAggregation == .unified else {
            return "Varies by job\nSee Summary"
        }

        return display(snapshot.projectedPaycheckGross, takeHome: snapshot.projectedPaycheckTakeHome)
            + "\n"
            + snapshot.projectedConfidenceLabel
    }

    private func payPeriodMetric(_ resolvedValue: String) -> String {
        guard snapshot.payPeriodAggregation == .unified else {
            return "Varies by job"
        }

        return resolvedValue
    }
}
