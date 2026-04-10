import Charts
import SwiftData
import SwiftUI

struct SummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppTheme.self) private var theme

    @Query private var preferences: [AppPreferences]
    @Query private var taxProfiles: [TaxProfile]
    @Query private var paySchedules: [PaySchedule]
    @Query(sort: \PayRateSchedule.effectiveDate, order: .reverse) private var payRates: [PayRateSchedule]
    @Query private var templates: [ScheduleTemplate]
    @Query(sort: \ShiftRecord.startDate, order: .reverse) private var shifts: [ShiftRecord]

    private var snapshot: SummarySnapshot {
        (try? ShiftController.summarySnapshot(in: modelContext, at: .now)) ?? .empty
    }

    private var mode: EarningsDisplayMode {
        preferences.first?.selectedDisplayMode ?? .gross
    }

    private var accent: Color {
        theme.accent(for: mode)
    }

    var body: some View {
        ZStack {
            MoneyBackground(mode: mode)

            ScrollView(showsIndicators: false) {
                VStack(spacing: Spacing.lg) {
                    BrandHeader(
                        eyebrow: "Summary",
                        subtitle: "Combined overview first, then each job's details.",
                        mode: mode,
                        compact: false
                    )

                    // MARK: - Earnings chart
                    if !shifts.isEmpty {
                        EarningsChart(
                            shifts: shifts,
                            mode: mode,
                            taxProfile: taxProfiles.first,
                            paySchedules: paySchedules,
                            payRates: payRates,
                            templates: templates
                        )
                    }

                    // MARK: - Combined card
                    SummaryJobCard(
                        title: "Combined",
                        accent: accent,
                        confidenceLabel: snapshot.projectedConfidenceLabel,
                        rollup: snapshot.combined,
                        mode: mode,
                        isCombined: true
                    )

                    // MARK: - Per-job cards
                    ForEach(snapshot.jobs) { job in
                        SummaryJobCard(
                            title: job.name,
                            accent: job.accent.color,
                            confidenceLabel: job.projectedConfidenceLabel,
                            rollup: job.rollup,
                            mode: mode,
                            isCombined: false
                        )
                    }
                }
                .padding(18)
                .padding(.bottom, 130)
            }
        }
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Earnings Chart

private struct EarningsChart: View {
    @Environment(AppTheme.self) private var theme

    let shifts: [ShiftRecord]
    let mode: EarningsDisplayMode
    let taxProfile: TaxProfile?
    let paySchedules: [PaySchedule]
    let payRates: [PayRateSchedule]
    let templates: [ScheduleTemplate]

    private struct WeekBucket: Identifiable {
        let id: Date
        let label: String
        var gross: Double = 0
        var takeHome: Double = 0
    }

    private var recentWeeks: [WeekBucket] {
        let calendar = Calendar.current
        var buckets: [Date: WeekBucket] = [:]

        // Build 6 week buckets ending with the current week
        let now = Date.now
        for weekOffset in (0..<6).reversed() {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: now),
                  let interval = calendar.dateInterval(of: .weekOfYear, for: weekStart) else { continue }

            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            let label = formatter.string(from: interval.start)
            buckets[interval.start] = WeekBucket(id: interval.start, label: label)
        }

        // Distribute shifts into buckets
        for shift in shifts {
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: shift.startDate) else { continue }
            if buckets[interval.start] != nil {
                buckets[interval.start]!.gross += shift.grossEarnings
                buckets[interval.start]!.takeHome += estimatedTakeHome(for: shift, calendar: calendar)
            }
        }

        return buckets.values.sorted { $0.id < $1.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accent(for: mode))
                Text("WEEKLY EARNINGS")
                    .font(TypeStyle.micro)
                    .tracking(1.4)
                    .foregroundStyle(theme.accent(for: mode).opacity(0.72))
            }

            Chart(recentWeeks) { week in
                BarMark(
                    x: .value("Week", week.label),
                    y: .value("Earnings", mode == .gross ? week.gross : week.takeHome)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [theme.accent(for: mode), theme.accent(for: mode).opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(6)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                        .foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(amount.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                }
            }
            .frame(height: 160)
        }
        .padding(Spacing.lg)
        .glassCard(cornerRadius: CornerRadius.cardLarge, accent: theme.accent(for: mode))
    }

    private func estimatedTakeHome(for shift: ShiftRecord, calendar: Calendar) -> Double {
        guard let taxProfile else {
            return shift.grossEarnings
        }

        return TaxEstimator.estimatedTakeHome(
            for: shift,
            allShifts: shifts,
            payRates: payRates,
            paySchedules: paySchedules,
            templates: templates,
            taxProfile: taxProfile,
            calendar: calendar
        )
    }
}

// MARK: - Job Card

private struct SummaryJobCard: View {
    @Environment(AppTheme.self) private var theme

    let title: String
    let accent: Color
    let confidenceLabel: String
    let rollup: SummaryRollup
    let mode: EarningsDisplayMode
    let isCombined: Bool

    // Collapsible section state — Pay Period and Projected default expanded
    @State private var expandedSections: Set<String> = ["Pay Period", "Projected Paycheck"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ──
            cardHeader
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Divider()
                .overlay(accent.opacity(0.18))

            // ── Sections ──
            VStack(spacing: 0) {
                // Active Now
                if rollup.activeShiftCount > 0 {
                    collapsibleSection(
                        title: "Active Now",
                        icon: "bolt.fill",
                        rows: [
                            ("Live Shifts", "\(rollup.activeShiftCount)"),
                            ("Gross", rollup.activeGross.asCurrency),
                            ("Take-Home", rollup.activeTakeHome.asCurrency),
                        ]
                    )
                }

                // Pay Period
                collapsibleSection(
                    title: "Pay Period",
                    icon: "calendar",
                    rows: payPeriodRows
                )

                // Projected
                collapsibleSection(
                    title: "Projected Paycheck",
                    icon: "chart.line.uptrend.xyaxis",
                    rows: projectedRows
                )

                // All Time
                collapsibleSection(
                    title: "All Time",
                    icon: "clock.arrow.circlepath",
                    rows: [
                        ("Gross", rollup.allTimeGross.asCurrency),
                        ("Take-Home", rollup.allTimeTakeHome.asCurrency),
                        ("Hours", rollup.allTimeHours.asHours),
                    ]
                )

                // Overtime & Premiums
                if rollup.totalOvertimeHours > 0 || rollup.totalNightPremium > 0 {
                    collapsibleSection(
                        title: "Overtime & Premiums",
                        icon: "moon.stars.fill",
                        rows: [
                            ("Overtime Hours", rollup.totalOvertimeHours.asHours),
                            ("Overtime Premium", rollup.totalOvertimePremium.asCurrency),
                            ("Night Premium (Lifetime)", rollup.totalNightPremium.asCurrency),
                        ]
                    )
                }

                // Averages & Records
                collapsibleSection(
                    title: "Averages & Records",
                    icon: "trophy.fill",
                    rows: [
                        ("Avg Shift Gross", rollup.averageShiftGross.asCurrency),
                        ("Avg Shift Hours", rollup.averageShiftHours.asHours),
                        ("Best Shift", rollup.highestShiftGross.asCurrency),
                        ("Blended Rate", rollup.currentBlendedRate.asCurrency + "/hr"),
                    ],
                    isLast: true
                )
            }
        }
        .glassCard(cornerRadius: CornerRadius.cardLarge, accent: accent)
    }

    // MARK: Header

    private var cardHeader: some View {
        HStack(spacing: 12) {
            JobInitialBadge(name: title, accent: accent, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(TypeStyle.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                statusLine
            }

            Spacer()

            // Hero figure: the mode-appropriate pay-period amount
            Text(heroAmount.asCurrency)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(accent)
        }
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            statusChip("\(rollup.completedShiftCount) done", icon: "checkmark.circle.fill")
            statusChip("\(rollup.scheduledShiftCount) scheduled", icon: "calendar.badge.clock")
            if rollup.activeShiftCount > 0 {
                statusChip("\(rollup.activeShiftCount) live", icon: "bolt.fill")
            }
        }
    }

    private func statusChip(_ text: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(theme.tertiaryText)
    }

    private var payPeriodRows: [(String, String)] {
        guard !(isCombined && rollup.payPeriodAggregation == .variesByJob) else {
            return [("Status", "Varies by job")]
        }

        return [
            ("Gross", rollup.payPeriodGross.asCurrency),
            ("Take-Home", rollup.payPeriodTakeHome.asCurrency),
            ("Hours", rollup.payPeriodHours.asHours),
            ("Night Premium", rollup.payPeriodNightPremium.asCurrency),
        ]
    }

    private var projectedRows: [(String, String)] {
        guard !(isCombined && rollup.payPeriodAggregation == .variesByJob) else {
            return [("Status", "Varies by job")]
        }

        return [
            ("Gross", rollup.projectedGross.asCurrency),
            ("Take-Home", rollup.projectedTakeHome.asCurrency),
            ("Confidence", confidenceLabel),
        ]
    }

    private var heroAmount: Double {
        guard !(isCombined && rollup.payPeriodAggregation == .variesByJob) else {
            if rollup.activeShiftCount > 0 {
                return mode == .gross ? rollup.activeGross : rollup.activeTakeHome
            }

            return mode == .gross ? rollup.allTimeGross : rollup.allTimeTakeHome
        }

        return mode == .gross ? rollup.payPeriodGross : rollup.payPeriodTakeHome
    }

    // MARK: Collapsible Section

    @ViewBuilder
    private func collapsibleSection(
        title: String,
        icon: String,
        rows: [(String, String)],
        isLast: Bool = false
    ) -> some View {
        let isExpanded = expandedSections.contains(title)

        VStack(alignment: .leading, spacing: 0) {
            // Tappable section header
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    if isExpanded {
                        expandedSections.remove(title)
                    } else {
                        expandedSections.insert(title)
                    }
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent.opacity(0.72))

                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(accent.opacity(0.72))

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(accent.opacity(0.4))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, isExpanded ? 10 : 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Collapsible rows
            if isExpanded {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    SummaryRow(label: row.0, value: row.1)
                        .padding(.horizontal, 20)

                    if index < rows.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.04))
                            .padding(.leading, 20)
                    }
                }
            }

            if !isLast {
                Divider()
                    .overlay(accent.opacity(0.10))
                    .padding(.top, isExpanded ? 12 : 0)
            } else {
                Spacer()
                    .frame(height: isExpanded ? 16 : 0)
            }
        }
    }
}

// MARK: - Row

private struct SummaryRow: View {
    @Environment(AppTheme.self) private var theme

    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(theme.secondaryText)

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 9)
    }
}

// MARK: - Formatting helpers

private extension Double {
    var asCurrency: String {
        formatted(.currency(code: "USD"))
    }

    var asHours: String {
        formatted(.number.precision(.fractionLength(1))) + " hrs"
    }
}

// MARK: - Empty state

private extension SummarySnapshot {
    static let empty = SummarySnapshot(
        combined: SummaryRollup(
            activeShiftCount: 0,
            scheduledShiftCount: 0,
            completedShiftCount: 0,
            activeGross: 0,
            activeTakeHome: 0,
            payPeriodAggregation: .unified,
            payPeriodGross: 0,
            payPeriodTakeHome: 0,
            payPeriodHours: 0,
            payPeriodNightPremium: 0,
            projectedGross: 0,
            projectedTakeHome: 0,
            allTimeGross: 0,
            allTimeTakeHome: 0,
            allTimeHours: 0,
            weeklyGross: 0,
            totalNightPremium: 0,
            totalOvertimePremium: 0,
            totalOvertimeHours: 0,
            averageShiftGross: 0,
            averageShiftHours: 0,
            highestShiftGross: 0,
            currentBlendedRate: 0
        ),
        projectedConfidenceLabel: "Earned so far",
        jobs: []
    )
}
