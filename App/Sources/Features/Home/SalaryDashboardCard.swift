import SwiftUI

struct SalaryDashboardCard: View {
    @Environment(AppTheme.self) private var theme
    let snapshot: SalaryDashboardSnapshot
    let mode: EarningsDisplayMode
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier) ?? .current
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                JobInitialBadge(name: snapshot.name, accent: snapshot.accent.color, size: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.name).font(TypeStyle.title3).foregroundStyle(TimecardColor.ink)
                    Text(
                        snapshot.isUpcoming
                            ? "Salary starts \(snapshot.effectiveDate.formatted(date: .abbreviated, time: .omitted))"
                            : "Automatic salary tracking"
                    )
                    .font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
                }
            }
            PayReadout(title: mode == .gross ? "Salary this period · gross" : "Salary this period · est. take-home",
                         amount: snapshot.amount(for: mode), mode: mode) {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: snapshot.progress).tint(mode == .gross ? TimecardColor.chalk : TimecardColor.ink)
                        .accessibilityLabel("Salary progress")
                    Text("\(snapshot.progress.formatted(.percent.precision(.fractionLength(0)))) of \(snapshot.expectedAmount(for: mode).formatted(.currency(code: "USD")))").monospacedDigit()
                    Text(SalaryEngine.displayRange(snapshot.interval, calendar: calendar)).font(.caption)
                }
            }
            AdaptiveCardGrid(minimumWidth: 125, spacing: 14) {
                metric("Today so far", mode == .gross ? snapshot.todayGross : snapshot.todayTakeHome)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next payday").font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
                    Text(SalaryEngine.dateLabel(snapshot.payday, calendar: calendar)).font(TypeStyle.title3)
                        .foregroundStyle(TimecardColor.ink)
                }
            }
            DisclosureGroup("Salary details") {
                VStack(alignment: .leading, spacing: 8) {
                    metric("Month to date · gross", snapshot.monthGross)
                    metric("Year to date · gross", snapshot.yearGross)
                    Text(snapshot.accrualDescription).font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let rate = snapshot.effectiveHourlyRate {
                Text(
                    "\(rate.formatted(.currency(code: "USD")))/hr across \(snapshot.loggedHours.formatted()) logged hours"
                )
                .font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
            }
            NavigationLink {
                SalaryHistoryView(jobIdentifier: snapshot.id)
            } label: {
                Label("Paychecks, hours & salary history", systemImage: "clock.arrow.circlepath")
                    .font(TypeStyle.callout).frame(minHeight: 44, alignment: .leading)
            }
            .tint(snapshot.accent.color)
        }
        .padding(.bottom, 12).ruledSection()
    }

    private func metric(_ title: String, _ amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
            Text(amount, format: .currency(code: "USD"))
                .font(TypeStyle.callout).monospacedDigit().foregroundStyle(TimecardColor.ink)
                .lineLimit(1).minimumScaleFactor(0.5)
        }.accessibilityElement(children: .combine)
    }
}
