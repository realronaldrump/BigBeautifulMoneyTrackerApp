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

            VStack(spacing: 14) {
                HStack {
                    Text("Beneath The Ticker")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                    Spacer()
                    Text(isExpanded ? "Hide" : "Reveal")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.secondaryText)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricTile(
                        title: "Pay Period",
                        value: display(snapshot.payPeriodGross, takeHome: snapshot.payPeriodTakeHome),
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
                            value: snapshot.payPeriodHours.formatted(.number.precision(.fractionLength(1))) + " hrs",
                            accent: theme.accent(for: mode)
                        )
                        MetricTile(
                            title: "Projected Check",
                            value: display(snapshot.projectedPaycheckGross, takeHome: snapshot.projectedPaycheckTakeHome) + "\n" + snapshot.projectedConfidenceLabel,
                            accent: theme.accent(for: mode)
                        )
                        MetricTile(
                            title: "Night Premium",
                            value: snapshot.payPeriodNightPremium.formatted(.currency(code: "USD")),
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
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(theme.panel.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
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
}
