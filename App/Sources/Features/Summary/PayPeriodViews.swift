import SwiftUI
import UIKit

struct PayPeriodArchivePreviewCard: View {
    @Environment(AppTheme.self) private var theme

    let snapshot: PayPeriodArchiveSnapshot
    let mode: EarningsDisplayMode

    private var latestSummary: PayPeriodSummary? {
        snapshot.latestSummary
    }

    var body: some View {
        NavigationLink {
            PayPeriodArchiveView(snapshot: snapshot, mode: mode)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Label("PAY PERIODS", systemImage: "calendar.badge.clock")
                            .font(TypeStyle.micro)
                            .tracking(1.4)
                            .foregroundStyle(theme.accent(for: mode).opacity(0.78))

                        Text("Big Beautiful Summaries")
                            .font(TypeStyle.title2)
                            .foregroundStyle(.white)

                        Text("Review recent pay cycles and export a Big Beautiful PDF for any period.")
                            .font(TypeStyle.caption)
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.tertiaryText)
                        .padding(.top, 4)
                }

                if let latestSummary {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(latestSummary.jobName)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(latestSummary.accent.color)

                            Text(latestSummary.interval.displayRange)
                                .font(TypeStyle.caption)
                                .foregroundStyle(theme.secondaryText)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 5) {
                            Text(latestSummary.displayAmount(for: mode).asCurrency)
                                .font(.system(size: 26, weight: .heavy, design: .rounded))
                                .foregroundStyle(theme.accent(for: mode))

                            Text(latestSummary.displaySummaryContext)
                                .font(TypeStyle.caption)
                                .foregroundStyle(theme.secondaryText)
                        }
                    }

                    HStack(spacing: 8) {
                        PayPeriodPill(text: "\(snapshot.sections.count) views", color: theme.accent(for: mode))
                        PayPeriodPill(text: "Last 12 months", color: theme.takeHomeAccent)
                        PayPeriodPill(text: "Big Beautiful Export", color: theme.roseAccent)
                    }
                } else {
                    Text("Pay summaries appear here once shifts are logged.")
                        .font(TypeStyle.caption)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .padding(Spacing.lg)
            .glassCard(cornerRadius: CornerRadius.cardLarge, accent: theme.accent(for: mode))
        }
        .buttonStyle(.plain)
    }
}

struct PayPeriodArchiveView: View {
    @Environment(AppTheme.self) private var theme

    let snapshot: PayPeriodArchiveSnapshot
    let mode: EarningsDisplayMode

    @State private var selectedSectionID: String?

    init(snapshot: PayPeriodArchiveSnapshot, mode: EarningsDisplayMode) {
        self.snapshot = snapshot
        self.mode = mode
        _selectedSectionID = State(initialValue: snapshot.defaultSectionID)
    }

    private var selectedSection: PayPeriodArchiveSection? {
        snapshot.sections.first { $0.id == selectedSectionID } ?? snapshot.sections.first
    }

    var body: some View {
        ZStack {
            MoneyBackground(mode: mode)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    BrandHeader(
                        eyebrow: "Pay Periods",
                        subtitle: "Review estimated personal pay summaries from your recent work history.",
                        mode: mode,
                        compact: false
                    )

                    if snapshot.sections.count > 1 {
                        sectionPicker
                    }

                    if let selectedSection {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            archiveHeader(for: selectedSection)

                            ForEach(selectedSection.summaries) { summary in
                                NavigationLink {
                                    PayPeriodDetailView(summary: summary, mode: mode)
                                } label: {
                            PayPeriodSummaryCard(summary: summary, mode: mode)
                        }
                        .buttonStyle(.plain)
                    }
                }
                    } else {
                        emptyState
                    }
                }
                .padding(18)
                .padding(.bottom, 130)
            }
        }
        .navigationTitle("Pay Periods")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(snapshot.sections) { section in
                    let isSelected = (selectedSection?.id ?? selectedSectionID) == section.id
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                            selectedSectionID = section.id
                        }
                    } label: {
                        HStack(spacing: 8) {
                            JobInitialBadge(
                                name: section.title,
                                accent: section.accent.color,
                                size: 26
                            )

                            Text(section.title)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .lineLimit(1)
                        }
                        .foregroundStyle(isSelected ? .white : theme.secondaryText)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background {
                            Capsule()
                                .fill(section.accent.color.opacity(isSelected ? 0.22 : 0.08))
                                .overlay {
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(isSelected ? 0.18 : 0.08), lineWidth: 1)
                                }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func archiveHeader(for section: PayPeriodArchiveSection) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .font(TypeStyle.title2)
                    .foregroundStyle(.white)
                Text(section.isCombined ? "Matching pay schedules only" : "\(section.summaries.count) recent pay periods")
                    .font(TypeStyle.caption)
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer()

            Text("Live estimates")
                .font(TypeStyle.caption)
                .foregroundStyle(section.accent.color)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)
            Text("No pay periods yet")
                .font(TypeStyle.title2)
                .foregroundStyle(.white)
            Text("Log shifts to build estimated pay summaries.")
                .font(TypeStyle.caption)
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .glassCard(cornerRadius: CornerRadius.cardLarge, accent: theme.accent(for: mode))
    }
}

private struct PayPeriodSummaryCard: View {
    @Environment(AppTheme.self) private var theme

    let summary: PayPeriodSummary
    let mode: EarningsDisplayMode

    private var accent: Color {
        summary.isCombined ? theme.accent(for: mode) : summary.accent.color
    }

    private var metricItems: [(String, String, String)] {
        if summary.isSupplementOnly {
            return [
                ("Supplements", summary.supplementMetricLabel, "plus.rectangle.on.folder"),
                ("Taxable", summary.supplementalTaxableTotal.asCurrency, "banknote"),
                ("Non-Taxable", summary.supplementalNonTaxableTotal.asCurrency, "checkmark.shield"),
            ]
        }

        var items: [(String, String, String)] = [
            ("Hours", summary.totalHours.asHours, "clock"),
            ("Shifts", "\(summary.shiftCount)", "checkmark.circle"),
        ]

        if summary.nightPremiumEarnings > 0 {
            items.append(("Night", summary.nightPremiumEarnings.asCurrency, "moon.stars"))
        }
        if summary.overtimePremiumEarnings > 0 {
            items.append(("OT", summary.overtimePremiumEarnings.asCurrency, "sparkles"))
        }

        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        PayPeriodPill(text: summary.status.title, color: statusColor)
                        if summary.isCombined {
                            PayPeriodPill(text: "Combined", color: theme.accent(for: mode))
                        }
                    }

                    Text(summary.interval.displayRange)
                        .font(TypeStyle.title3)
                        .foregroundStyle(.white)

                    Text(summary.frequency.title)
                        .font(TypeStyle.caption)
                        .foregroundStyle(theme.secondaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    Text(summary.displayAmount(for: mode).asCurrency)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(theme.accent(for: mode))

                    Text(summary.displayModeCaption(for: mode).lowercased())
                        .font(TypeStyle.micro)
                        .foregroundStyle(theme.tertiaryText)
                }
            }

            HStack(spacing: 10) {
                ForEach(Array(metricItems.enumerated()), id: \.offset) { _, item in
                    metric(item.0, item.1, systemImage: item.2)
                }
            }
        }
        .padding(18)
        .glassCard(cornerRadius: CornerRadius.cardLarge, accent: accent)
    }

    private var statusColor: Color {
        switch summary.status {
        case .current:
            theme.grossAccent
        case .closed:
            summary.accent.color
        }
    }

    private func metric(_ title: String, _ value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.tertiaryText)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PayPeriodDetailView: View {
    @Environment(AppTheme.self) private var theme

    let summary: PayPeriodSummary
    let mode: EarningsDisplayMode

    @State private var exportItem: PayPeriodExportItem?
    @State private var exportErrorText: String?

    private var accent: Color {
        summary.isCombined ? theme.accent(for: mode) : summary.accent.color
    }

    private var metricTileItems: [(String, String, Color)] {
        if summary.isSupplementOnly {
            return [
                (summary.displayMetricTitle(for: .gross), summary.displayGrossAmount.asCurrency, theme.grossAccent),
                (summary.displayMetricTitle(for: .takeHome), summary.displayTakeHomeAmount.asCurrency, theme.takeHomeAccent),
                ("Supplement Total", summary.supplementalTotal.asCurrency, accent),
                ("Taxable Portion", summary.supplementalTaxableTotal.asCurrency, accent),
                ("Non-Taxable Portion", summary.supplementalNonTaxableTotal.asCurrency, theme.takeHomeAccent),
                ("Effective Rate", summary.displayHourlyRate.map { $0.asHourlyRate } ?? "Unavailable", accent),
            ]
        }

        return [
            (summary.displayMetricTitle(for: .gross), summary.displayGrossAmount.asCurrency, theme.grossAccent),
            (summary.displayMetricTitle(for: .takeHome, condensed: true), summary.displayTakeHomeAmount.asCurrency, theme.takeHomeAccent),
            ("Hours", summary.totalHours.asHours, accent),
            ("Shifts", "\(summary.shiftCount)", accent),
            ("Effective Rate", summary.displayHourlyRate.map { $0.asHourlyRate } ?? "Unavailable", accent),
            ("Best Shift", summary.bestShiftGross.asCurrency, accent),
        ]
    }

    var body: some View {
        ZStack {
            MoneyBackground(mode: mode)

            ScrollView(showsIndicators: false) {
                VStack(spacing: Spacing.lg) {
                    heroCard
                    metricsGrid
                    if hasSupplementalContent {
                        supplementalCard
                        effectiveEarningsCard
                    }
                    breakdownCard

                    if !summary.shifts.isEmpty {
                        shiftList
                    }
                }
                .padding(18)
                .padding(.bottom, 130)
            }
        }
        .navigationTitle("Pay Summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportPDF()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export PDF")
            }
        }
        .sheet(item: $exportItem) { item in
            PayPeriodActivityView(activityItems: [item.url])
        }
        .alert("Unable to Export PDF", isPresented: exportErrorIsPresented) {
            Button("OK") {
                exportErrorText = nil
            }
        } message: {
            Text(exportErrorText ?? "")
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.md) {
                JobInitialBadge(name: summary.jobName, accent: accent, size: 44)

                VStack(alignment: .leading, spacing: 5) {
                    Text(summary.jobName)
                        .font(TypeStyle.title2)
                        .foregroundStyle(.white)

                    Text("Big Beautiful Summary")
                        .font(TypeStyle.caption)
                        .foregroundStyle(theme.secondaryText)
                }

                Spacer()

                PayPeriodPill(text: summary.status.title, color: statusColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(summary.interval.displayRange)
                    .font(TypeStyle.title3)
                    .foregroundStyle(theme.secondaryText)

                Text(summary.displayAmount(for: mode).asCurrency)
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.accent(for: mode))
                    .minimumScaleFactor(0.7)

                Text(summary.displayModeCaption(for: mode))
                    .font(TypeStyle.caption)
                    .foregroundStyle(theme.tertiaryText)
            }

            Text("This is a personal estimate from your tracked shifts, pay rules, and tax settings. It is not an employer-issued pay stub.")
                .font(TypeStyle.caption)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .glassCard(cornerRadius: CornerRadius.cardLarge, accent: accent)
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(Array(metricTileItems.enumerated()), id: \.offset) { _, item in
                PayPeriodMetricTile(title: item.0, value: item.1, accent: item.2)
            }
        }
    }

    private var hasSupplementalContent: Bool {
        summary.hasSupplementalCompensation
    }

    private var supplementalCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Supplemental Compensation")
                .font(TypeStyle.title3)
                .foregroundStyle(.white)
                .padding(.bottom, 12)

            if summary.supplementAllocations.isEmpty {
                PayPeriodDetailRow(label: "Supplements in this period", value: summary.supplementalTotal.asCurrency)
            } else {
                ForEach(Array(summary.supplementAllocations.enumerated()), id: \.offset) { index, allocation in
                    PayPeriodSupplementRow(
                        allocation: allocation,
                        showsJobName: summary.isCombined
                    )
                    if index < summary.supplementAllocations.count - 1 {
                        PayPeriodDivider()
                    }
                }
            }

            PayPeriodDivider()
            PayPeriodDetailRow(label: "Taxable Portion", value: summary.supplementalTaxableTotal.asCurrency)
            PayPeriodDivider()
            PayPeriodDetailRow(label: "Non-Taxable Portion", value: summary.supplementalNonTaxableTotal.asCurrency)
            PayPeriodDivider()
            PayPeriodDetailRow(label: "Supplement Total", value: summary.supplementalTotal.asCurrency)
        }
        .padding(Spacing.lg)
        .glassCard(cornerRadius: CornerRadius.cardLarge, accent: theme.takeHomeAccent)
    }

    private var effectiveEarningsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Effective Earnings")
                .font(TypeStyle.title3)
                .foregroundStyle(.white)
                .padding(.bottom, 12)

            PayPeriodDetailRow(label: "Effective Gross", value: summary.effectiveGross.asCurrency)
            PayPeriodDivider()
            PayPeriodDetailRow(label: "Effective Take-Home", value: summary.effectiveTakeHome.asCurrency)
            PayPeriodDivider()
            PayPeriodDetailRow(
                label: "Effective Hourly Rate",
                value: summary.effectiveSupplementalHourlyRate.map { $0.asHourlyRate } ?? "Unavailable"
            )
        }
        .padding(Spacing.lg)
        .glassCard(cornerRadius: CornerRadius.cardLarge, accent: accent)
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Breakdown")
                .font(TypeStyle.title3)
                .foregroundStyle(.white)
                .padding(.bottom, 12)

            PayPeriodDetailRow(label: "Base Earnings", value: summary.baseEarnings.asCurrency)
            PayPeriodDivider()
            PayPeriodDetailRow(label: "Night Premium", value: summary.nightPremiumEarnings.asCurrency)
            PayPeriodDivider()
            PayPeriodDetailRow(label: "Overtime Premium", value: summary.overtimePremiumEarnings.asCurrency)
            PayPeriodDivider()
            PayPeriodDetailRow(label: "Regular Hours", value: summary.regularHours.asHours)
            PayPeriodDivider()
            PayPeriodDetailRow(label: "Night Hours", value: summary.nightHours.asHours)
            PayPeriodDivider()
            PayPeriodDetailRow(label: "Overtime Hours", value: summary.overtimeHours.asHours)
        }
        .padding(Spacing.lg)
        .glassCard(cornerRadius: CornerRadius.cardLarge, accent: accent)
    }

    private var shiftList: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Included Shifts")
                    .font(TypeStyle.title3)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(summary.shiftCount)")
                    .font(TypeStyle.caption)
                    .foregroundStyle(theme.secondaryText)
            }

            ForEach(summary.shifts.sorted { $0.allocatedStartDate > $1.allocatedStartDate }) { shift in
                PayPeriodShiftRow(shift: shift, mode: mode, accent: shift.jobIdentifier == nil ? accent : summary.accent.color)
            }
        }
    }

    private var statusColor: Color {
        switch summary.status {
        case .current:
            theme.grossAccent
        case .closed:
            accent
        }
    }

    private var exportErrorIsPresented: Binding<Bool> {
        Binding(
            get: { exportErrorText != nil },
            set: { isPresented in
                if !isPresented {
                    exportErrorText = nil
                }
            }
        )
    }

    private func exportPDF() {
        do {
            let url = try PayPeriodPDFExporter.export(summary: summary)
            exportItem = PayPeriodExportItem(url: url)
        } catch {
            exportErrorText = error.localizedDescription
        }
    }
}

private struct PayPeriodMetricTile: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(TypeStyle.micro)
                .tracking(1.2)
                .foregroundStyle(accent.opacity(0.72))

            Text(value)
                .font(TypeStyle.title2)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: CornerRadius.cardSmall, accent: accent, hasShadow: false)
    }
}

private struct PayPeriodDetailRow: View {
    @Environment(AppTheme.self) private var theme

    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(TypeStyle.callout)
                .foregroundStyle(theme.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 9)
    }
}

private struct PayPeriodSupplementRow: View {
    @Environment(AppTheme.self) private var theme

    let allocation: JobSupplementAllocation
    let showsJobName: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(primaryLabel)
                    .font(TypeStyle.callout)
                    .foregroundStyle(.white)

                Text(secondaryLabel)
                    .font(TypeStyle.caption)
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer()

            Text(allocation.amount.asCurrency)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 9)
    }

    private var primaryLabel: String {
        showsJobName ? "\(allocation.jobName) • \(allocation.label)" : allocation.label
    }

    private var secondaryLabel: String {
        let taxLabel = allocation.taxableAmount > 0 ? "Taxable" : "Non-taxable"
        return "\(allocation.kind.title) • \(allocation.frequency.title) • \(taxLabel)"
    }
}

private struct PayPeriodShiftRow: View {
    @Environment(AppTheme.self) private var theme

    let shift: PayPeriodShiftSummary
    let mode: EarningsDisplayMode
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(shift.jobName)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)

                    Text(shift.allocatedStartDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(timeRange)
                        .font(TypeStyle.caption)
                        .foregroundStyle(theme.secondaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    Text(shift.displayAmount(for: mode).asCurrency)
                        .font(TypeStyle.title2)
                        .foregroundStyle(theme.accent(for: mode))
                    Text(shift.totalHours.asHours)
                        .font(TypeStyle.caption)
                        .foregroundStyle(theme.secondaryText)
                }
            }

            HStack(spacing: 10) {
                PayPeriodPill(text: "\(shift.regularHours.oneDecimal) reg", color: theme.grossAccent)
                if shift.nightHours > 0 {
                    PayPeriodPill(text: "\(shift.nightHours.oneDecimal) night", color: accent)
                }
                if shift.overtimeHours > 0 {
                    PayPeriodPill(text: "\(shift.overtimeHours.oneDecimal) OT", color: theme.takeHomeAccent)
                }
                if shift.isPartial {
                    PayPeriodPill(text: "Partial", color: theme.roseAccent)
                }
                if shift.isActive {
                    PayPeriodPill(text: "Active", color: theme.grossAccent)
                }
            }

            if !shift.note.isEmpty {
                Text(shift.note)
                    .font(TypeStyle.caption)
                    .foregroundStyle(Color.white.opacity(0.86))
            }
        }
        .padding(18)
        .glassCard(cornerRadius: CornerRadius.cardLarge, accent: accent)
    }

    private var timeRange: String {
        "\(shift.allocatedStartDate.formatted(date: .omitted, time: .shortened)) - \(shift.allocatedEndDate.formatted(date: .omitted, time: .shortened))"
    }
}

private struct PayPeriodPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.18))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(color.opacity(0.25), lineWidth: 1)
            }
    }
}

private struct PayPeriodDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.white.opacity(0.05))
    }
}

private struct PayPeriodExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PayPeriodActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension PayPeriodSummary {
    private static let presentationEpsilon = 0.000_001

    var hasSupplementalCompensation: Bool {
        supplementalTotal > Self.presentationEpsilon || !supplementAllocations.isEmpty
    }

    var isSupplementOnly: Bool {
        hasSupplementalCompensation
            && shiftCount == 0
            && grossEarnings <= Self.presentationEpsilon
            && totalHours <= Self.presentationEpsilon
    }

    var displayGrossAmount: Double {
        isSupplementOnly ? effectiveGross : grossEarnings
    }

    var displayTakeHomeAmount: Double {
        isSupplementOnly ? effectiveTakeHome : estimatedTakeHome
    }

    var displayHourlyRate: Double? {
        if hasSupplementalCompensation {
            return effectiveSupplementalHourlyRate
        }
        guard totalHours > Self.presentationEpsilon else {
            return nil
        }
        return effectiveHourlyRate
    }

    func displayAmount(for mode: EarningsDisplayMode) -> Double {
        mode == .gross ? displayGrossAmount : displayTakeHomeAmount
    }

    func displayMetricTitle(for mode: EarningsDisplayMode, condensed: Bool = false) -> String {
        switch mode {
        case .gross:
            isSupplementOnly ? "Effective Gross" : "Gross"
        case .takeHome:
            if isSupplementOnly {
                "Effective Take-Home"
            } else {
                condensed ? "Est. Take-Home" : "Estimated Take-Home"
            }
        }
    }

    func displayModeCaption(for mode: EarningsDisplayMode) -> String {
        switch mode {
        case .gross:
            isSupplementOnly ? "Effective gross" : "Gross earnings"
        case .takeHome:
            isSupplementOnly ? "Effective take-home" : "Estimated take-home"
        }
    }

    var supplementDisplayCount: Int {
        if !supplementAllocations.isEmpty {
            return supplementAllocations.count
        }
        return hasSupplementalCompensation ? 1 : 0
    }

    var supplementContextLabel: String {
        switch supplementDisplayCount {
        case 0:
            "Supplemental pay"
        case 1:
            "1 supplement"
        default:
            "\(supplementDisplayCount) supplements"
        }
    }

    var supplementMetricLabel: String {
        switch supplementDisplayCount {
        case 0:
            "Recurring"
        case 1:
            "1 item"
        default:
            "\(supplementDisplayCount) items"
        }
    }

    var displaySummaryContext: String {
        if isSupplementOnly {
            return "\(supplementContextLabel) • no shifts"
        }

        let shiftLabel = shiftCount == 1 ? "shift" : "shifts"
        let hours = totalHours.formatted(.number.precision(.fractionLength(1)))
        return "\(hours) hrs • \(shiftCount) \(shiftLabel)"
    }
}

private extension PayPeriodShiftSummary {
    func displayAmount(for mode: EarningsDisplayMode) -> Double {
        mode == .gross ? grossEarnings : estimatedTakeHome
    }
}

private extension DateInterval {
    var displayRange: String {
        let endDisplayDate = Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end
        return "\(start.formatted(date: .abbreviated, time: .omitted)) - \(endDisplayDate.formatted(date: .abbreviated, time: .omitted))"
    }
}

private extension Double {
    var asCurrency: String {
        formatted(.currency(code: "USD"))
    }

    var asHours: String {
        formatted(.number.precision(.fractionLength(1))) + " hrs"
    }

    var asHourlyRate: String {
        asCurrency + "/hr"
    }

    var oneDecimal: String {
        formatted(.number.precision(.fractionLength(1)))
    }
}
