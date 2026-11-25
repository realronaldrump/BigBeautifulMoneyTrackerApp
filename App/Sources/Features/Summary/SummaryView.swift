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
    @Query private var salaryPlans: [SalaryPlan]
    @Query private var salaryWorkLogs: [SalaryWorkLog]
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
            taxProfile: taxProfiles.first ?? TaxProfile(),
            salaryPlans: salaryPlans, salaryWorkLogs: salaryWorkLogs
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
            MoneyBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: Spacing.lg) {
                    TimecardHeading(title: "Earnings", detail: Date.now.formatted(.dateTime.month(.wide).year()))
                    if snapshot.jobs.count == 1 && !jobs.contains(where: \.isArchived), let job = snapshot.jobs.first {
                        SummaryJobCard(title: job.name, accent: job.accent.color, confidenceLabel: job.projectedConfidenceLabel,
                                       rollup: job.rollup, mode: mode, isCombined: false)
                    } else {
                        SummaryJobCard(title: "All jobs", accent: accent, confidenceLabel: snapshot.projectedConfidenceLabel,
                                       rollup: snapshot.combined, mode: mode, isCombined: true)
                    }

                    // MARK: - Earnings chart
                    if !shifts.isEmpty || !salaryPlans.isEmpty {
                        WeeklyEarningsChart(
                            shifts: shifts,
                            mode: mode,
                            taxProfile: taxProfiles.first,
                            paySchedules: paySchedules,
                            payRates: payRates,
                            templates: templates,
                            nightRules: nightRules,
                            overtimeRules: overtimeRules,
                            salaryPlans: salaryPlans, jobs: jobs
                        )
                    }

                    if !payPeriodArchive.sections.isEmpty {
                        PayPeriodArchivePreviewCard(snapshot: payPeriodArchive, mode: mode)
                    }

                    // MARK: - Per-job cards
                    if snapshot.jobs.count > 1 || jobs.contains(where: \.isArchived) {
                        DisclosureGroup("By job") {
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

private struct WeeklyEarningsChart: View {

    let shifts: [ShiftRecord]
    let mode: EarningsDisplayMode
    let taxProfile: TaxProfile?
    let paySchedules: [PaySchedule]
    let payRates: [PayRateSchedule]
    let templates: [ScheduleTemplate]
    let nightRules: [NightDifferentialRule]
    let overtimeRules: [OvertimeRuleSet]
    var salaryPlans: [SalaryPlan] = []
    var jobs: [JobProfile] = []

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

            let label = interval.start.formatted(.dateTime.month(.abbreviated).day())
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

        for job in jobs {
            let plans = salaryPlans.filter { $0.job?.id == job.id }
            guard !plans.isEmpty else { continue }
            let cutoff = job.isArchived ? min(now, job.archivedAt ?? job.updatedAt) : now
            let plan = SalaryEngine.activePlan(in: plans, at: cutoff.addingTimeInterval(-0.001)) ?? plans.max { $0.effectiveDate < $1.effectiveDate }!
            let estimate = TaxEstimator.estimate(currentGross: 0, annualizedGrossIncome: plan.annualGross,
                annualExtraWithholding: TaxEstimator.annualExtraWithholding(payFrequency: plan.frequency, taxProfile: taxProfile ?? TaxProfile()),
                taxProfile: taxProfile ?? TaxProfile(), payFrequency: plan.frequency, paycheck: job.paycheckReference)
            for start in Array(buckets.keys) {
                guard let interval = calendar.dateInterval(of: .weekOfYear, for: start) else { continue }
                let gross = SalaryEngine.gross(for: plans, within: interval, through: cutoff)
                buckets[start]?.gross += gross
                buckets[start]?.takeHome += TaxEstimator.estimatedTakeHome(for: gross, estimate: estimate)
            }
        }
        return buckets.values.sorted { $0.id < $1.id }
    }

    var body: some View {
        let weeks = recentWeeks
        let maximum = weeks.map { mode == .gross ? $0.gross : $0.takeHome }.max() ?? 0
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Weekly earnings").font(TypeStyle.title2).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(mode == .gross ? "Gross pay" : "Est. take-home")
                    .font(TimecardType.label).foregroundStyle(TimecardColor.graphite)
            }
            Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                ForEach(weeks) { week in
                    let value = mode == .gross ? week.gross : week.takeHome
                    let isCurrent = week.id == weeks.last?.id
                    GridRow {
                        Text(isCurrent ? "This week" : week.label).font(.caption.monospacedDigit())
                            .gridColumnAlignment(.leading)
                        GeometryReader { proxy in
                            let fraction = maximum > 0 ? min(1, max(0, value / maximum)) : 0
                            Rectangle().fill(TimecardColor.inset)
                                .overlay(alignment: .leading) {
                                    Rectangle().fill(isCurrent ? TimecardColor.redInk : TimecardColor.blueInk)
                                        .frame(width: proxy.size.width * fraction)
                                }
                        }
                        .frame(height: 7).accessibilityHidden(true)
                        Text(value, format: .currency(code: "USD")).font(.subheadline.monospacedDigit())
                            .gridColumnAlignment(.trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Week of " + week.label)
                    .accessibilityValue(value.formatted(.currency(code: "USD")))
                }
            }
        }
        .foregroundStyle(TimecardColor.ink)
        .padding(.bottom, 16).ruledSection()
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

    @State private var expandedSections: Set<String> = ["Pay Period"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            DisclosureGroup("Earnings breakdown") {
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

                    // Averages apply to tracked hourly shifts.
                    if rollup.completedShiftCount > 0 {
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
                    } else if rollup.salaryJobCount > 0 {
                        collapsibleSection(title: "Salary", icon: "banknote.fill", rows: [
                            ("Accrued this period", rollup.salaryGross.asCurrency),
                            ("All-time salary", rollup.salaryAllTimeGross.asCurrency),
                            ("Optional logged hours", rollup.salaryLoggedHours.asHours),
                            ("Basis", "Automatic visualization estimate")
                        ], isLast: true)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .ruledSection()
    }

    // MARK: Header

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(TypeStyle.title3)
            Text(heroContext).font(TimecardType.label).textCase(.uppercase).foregroundStyle(TimecardColor.graphite)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    statementAmount(.gross).fixedSize()
                    Spacer(minLength: 0)
                    statementAmount(.takeHome).fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    statementAmount(.gross)
                    statementAmount(.takeHome)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statementAmount(_ displayMode: EarningsDisplayMode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(displayMode == .gross ? "Gross pay" : "Est. take-home").font(.caption)
            Text(amount(for: displayMode), format: .currency(code: "USD"))
                .font(TimecardType.display(43, relativeTo: .largeTitle)).monospacedDigit()
                .foregroundStyle(displayMode == mode ? TimecardColor.blueInk : TimecardColor.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private var heroContext: String {
        if isCombined && rollup.payPeriodAggregation == .variesByJob {
            return rollup.activeShiftCount > 0 ? "Active shifts" : "All time"
        }
        return "Current pay period"
    }

    private var payPeriodRows: [(String, String)] {
        guard !(isCombined && rollup.payPeriodAggregation == .variesByJob) else {
            return [("Status", "Varies by job")]
        }

        if rollup.salaryJobCount > 0 {
            return [("Gross accrued", rollup.payPeriodGross.asCurrency),
                ("Est. take-home", rollup.payPeriodTakeHome.asCurrency),
                ("Salary portion", rollup.salaryGross.asCurrency),
                ("Optional salary hours", rollup.salaryLoggedHours.asHours)]
        }
        return [
            ("Gross", rollup.payPeriodGross.asCurrency),
            ("Est. take-home", rollup.payPeriodTakeHome.asCurrency),
            ("Hours", rollup.payPeriodHours.asHours),
        ] + (rollup.payPeriodNightPremium > 0 ? [("Night premium", rollup.payPeriodNightPremium.asCurrency)] : [])
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

    private func amount(for mode: EarningsDisplayMode) -> Double {
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
                        .font(.system(.caption2, design: .default, weight: .bold))
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
                            .overlay(TimecardColor.ink.opacity(0.04))
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
