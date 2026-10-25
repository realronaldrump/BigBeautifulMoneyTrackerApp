import Charts
import SwiftData
import SwiftUI

struct SummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppTheme.self) private var theme

    @Query private var preferences: [AppPreferences]
    @Query private var taxProfiles: [TaxProfile]
    @Query(sort: \JobProfile.sortOrder) private var jobs: [JobProfile]
    @Query(sort: \OpenShiftState.startDate) private var openShifts: [OpenShiftState]
    @Query private var paySchedules: [PaySchedule]
    @Query(sort: \PayRateSchedule.effectiveDate, order: .reverse) private var payRates: [PayRateSchedule]
    @Query private var nightRules: [NightDifferentialRule]
    @Query private var overtimeRules: [OvertimeRuleSet]
    @Query private var supplements: [JobSupplement]
    @Query private var templates: [ScheduleTemplate]
    @Query(sort: \ShiftRecord.startDate, order: .reverse) private var shifts: [ShiftRecord]

    private var mode: EarningsDisplayMode {
        preferences.first?.selectedDisplayMode ?? .gross
    }

    private var accent: Color {
        theme.accent(for: mode)
    }

    private func payPeriodArchive(asOf date: Date) -> PayPeriodArchiveSnapshot {
        PayPeriodService.archiveSnapshot(
            asOf: date,
            jobs: jobs,
            completedShifts: shifts,
            openShifts: openShifts,
            paySchedules: paySchedules,
            payRates: payRates,
            nightRules: nightRules,
            overtimeRules: overtimeRules,
            supplements: supplements,
            templates: templates,
            taxProfile: taxProfiles.first ?? TaxProfile()
        )
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            if let snapshot = try? ShiftController.summarySnapshot(in: modelContext, at: timeline.date) {
                summaryContent(snapshot: snapshot, payPeriodArchive: payPeriodArchive(asOf: timeline.date))
            } else {
                ContentUnavailableView("Unable to Load Summary", systemImage: "externaldrive.badge.exclamationmark", description: Text("Your saved data could not be read. Reopen the app to try again."))
            }
        }
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summaryContent(snapshot: SummarySnapshot, payPeriodArchive: PayPeriodArchiveSnapshot) -> some View {
        ZStack {
            MoneyBackground(mode: mode)

            ScrollView(showsIndicators: false) {
                VStack(spacing: Spacing.lg) {
                    BrandHeader(
                        eyebrow: "Summary",
                        subtitle: "Your earnings at a glance, with details for each job.",
                        mode: mode,
                        compact: true
                    )

                    // MARK: - Combined card
                    SummaryJobCard(
                        title: "Combined",
                        accent: accent,
                        confidenceLabel: snapshot.projectedConfidenceLabel,
                        rollup: snapshot.combined,
                        mode: mode,
                        isCombined: true
                    )

                    // MARK: - Earnings chart
                    if !shifts.isEmpty {
                        EarningsChart(
                            shifts: shifts,
                            mode: mode,
                            taxProfile: taxProfiles.first,
                            paySchedules: paySchedules,
                            payRates: payRates,
                            templates: templates,
                            nightRules: nightRules,
                            overtimeRules: overtimeRules
                        )
                    }

                    if !payPeriodArchive.sections.isEmpty {
                        PayPeriodArchivePreviewCard(snapshot: payPeriodArchive, mode: mode)
                    }

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
                .padding(.bottom, 24)
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
    let nightRules: [NightDifferentialRule]
    let overtimeRules: [OvertimeRuleSet]

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

        // Allocate crossing shifts using the same segments as the pay archive.
        for shift in shifts {
            let takeHomeRatio = shift.grossEarnings > 0 ? estimatedTakeHome(for: shift, calendar: calendar) / shift.grossEarnings : 0
            let configuration = shift.job.map {
                JobService.configuration(for: $0, payRates: payRates, nightRules: nightRules, overtimeRules: overtimeRules, paySchedules: paySchedules, templates: templates)
            }
            for start in Array(buckets.keys) {
                guard let interval = calendar.dateInterval(of: .weekOfYear, for: start) else { continue }
                let gross = configuration.map {
                    ShiftEarningsAllocation.completed(shift, within: interval, configuration: $0, historicalShifts: shifts.filter { $0.job?.id == shift.job?.id }, calendar: calendar).grossEarnings
                } ?? AggregationService.totalGross(for: [shift], in: interval)
                buckets[start]?.gross += gross
                buckets[start]?.takeHome += gross * takeHomeRatio
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
                .accessibilityLabel(Text("Week of \(week.label)"))
                .accessibilityValue(Text((mode == .gross ? week.gross : week.takeHome).formatted(.currency(code: "USD"))))
            }
            .accessibilityLabel(mode == .gross ? "Weekly gross earnings" : "Weekly estimated take-home")
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                        .foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(amount.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                                .font(.system(.caption2, design: .rounded, weight: .medium))
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
                                .font(.system(.caption2, design: .rounded, weight: .medium))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                            ("Est. take-home", rollup.activeTakeHome.asCurrency),
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

                if rollup.hasSupplementConfiguration {
                    collapsibleSection(
                        title: "Supplements & Effective",
                        icon: "plus.rectangle.on.folder.fill",
                        rows: supplementalRows
                    )
                }

                // All Time
                collapsibleSection(
                    title: "All Time",
                    icon: "clock.arrow.circlepath",
                    rows: [
                        ("Gross", rollup.allTimeGross.asCurrency),
                        ("Est. take-home", rollup.allTimeTakeHome.asCurrency),
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                JobInitialBadge(name: title, accent: accent, size: 36)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(TypeStyle.title2).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(rollup.completedShiftCount) completed · \(rollup.scheduledShiftCount) scheduled" + (rollup.activeShiftCount > 0 ? " · \(rollup.activeShiftCount) active" : ""))
                        .font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(heroContext).font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
                Text(heroAmount.asCurrency)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(accent).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.35)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroContext: String {
        let basis = isCombined && rollup.payPeriodAggregation == .variesByJob
            ? (rollup.activeShiftCount > 0 ? "Active shifts" : "All time") : "Current pay period"
        return basis + " · " + (mode == .gross ? "gross earnings" : "estimated take-home")
    }

    private var payPeriodRows: [(String, String)] {
        guard !(isCombined && rollup.payPeriodAggregation == .variesByJob) else {
            return [("Status", "Varies by job")]
        }

        return [
            ("Gross", rollup.payPeriodGross.asCurrency),
            ("Est. take-home", rollup.payPeriodTakeHome.asCurrency),
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
            ("Est. take-home", rollup.projectedTakeHome.asCurrency),
            ("Projection basis", confidenceLabel),
        ]
    }

    private var supplementalRows: [(String, String)] {
        var rows: [(String, String)] = []

        if isCombined && rollup.payPeriodAggregation == .variesByJob {
            rows.append(("Pay Period Supplement", "Varies by job"))
            rows.append(("Projected Supplement", "Varies by job"))
            rows.append(("Pay Period Effective Gross", "Varies by job"))
            rows.append(("Pay Period Effective Take-Home", "Varies by job"))
            rows.append(("Pay Period Effective Rate", "Varies by job"))
        } else {
            rows.append(("Pay Period Supplement", rollup.payPeriodEffective.supplementalTotal.asCurrency))
            rows.append(("Projected Supplement", rollup.projectedEffective.supplementalTotal.asCurrency))
            rows.append(("Pay Period Effective Gross", rollup.payPeriodEffective.effectiveGross.asCurrency))
            rows.append(("Pay Period Effective Take-Home", rollup.payPeriodEffective.effectiveTakeHome.asCurrency))
            rows.append(("Pay Period Effective Rate", effectiveRateLabel(rollup.payPeriodEffective.effectiveHourlyRate)))
        }

        rows.append(("All-Time Supplement", rollup.allTimeEffective.supplementalTotal.asCurrency))
        rows.append(("All-Time Effective Gross", rollup.allTimeEffective.effectiveGross.asCurrency))
        rows.append(("All-Time Effective Take-Home", rollup.allTimeEffective.effectiveTakeHome.asCurrency))
        rows.append(("All-Time Effective Rate", effectiveRateLabel(rollup.allTimeEffective.effectiveHourlyRate)))

        return rows
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

    private func effectiveRateLabel(_ value: Double?) -> String {
        guard let value else {
            return "Unavailable"
        }

        return value.asCurrency + "/hr"
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
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82)) {
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

                    Text(title)
                        .font(.system(.caption2, design: .rounded, weight: .bold))
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
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Hide details" : "Show details")

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

    var body: some View { AppValueRow(title: label, value: value) }
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
