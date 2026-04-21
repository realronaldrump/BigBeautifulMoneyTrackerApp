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

                        Text("Estimated Pay Summaries")
                            .font(TypeStyle.title2)
                            .foregroundStyle(.white)

                        Text("Review recent pay cycles and export a clean PDF for any period.")
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

                            Text("\(latestSummary.totalHours.asHours) • \(latestSummary.shiftCount) shifts")
                                .font(TypeStyle.caption)
                                .foregroundStyle(theme.secondaryText)
                        }
                    }

                    HStack(spacing: 8) {
                        PayPeriodPill(text: "\(snapshot.sections.count) views", color: theme.accent(for: mode))
                        PayPeriodPill(text: "Last 12 months", color: theme.takeHomeAccent)
                        PayPeriodPill(text: "PDF export", color: theme.roseAccent)
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

                    Text(mode == .gross ? "gross" : "est. take-home")
                        .font(TypeStyle.micro)
                        .foregroundStyle(theme.tertiaryText)
                }
            }

            HStack(spacing: 10) {
                metric("Hours", summary.totalHours.asHours, systemImage: "clock")
                metric("Shifts", "\(summary.shiftCount)", systemImage: "checkmark.circle")
                if summary.nightPremiumEarnings > 0 {
                    metric("Night", summary.nightPremiumEarnings.asCurrency, systemImage: "moon.stars")
                }
                if summary.overtimePremiumEarnings > 0 {
                    metric("OT", summary.overtimePremiumEarnings.asCurrency, systemImage: "sparkles")
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

    var body: some View {
        ZStack {
            MoneyBackground(mode: mode)

            ScrollView(showsIndicators: false) {
                VStack(spacing: Spacing.lg) {
                    heroCard
                    metricsGrid
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

                    Text("Estimated personal pay summary")
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

                Text(mode == .gross ? "Gross earnings" : "Estimated take-home")
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
            PayPeriodMetricTile(title: "Gross", value: summary.grossEarnings.asCurrency, accent: theme.grossAccent)
            PayPeriodMetricTile(title: "Est. Take-Home", value: summary.estimatedTakeHome.asCurrency, accent: theme.takeHomeAccent)
            PayPeriodMetricTile(title: "Hours", value: summary.totalHours.asHours, accent: accent)
            PayPeriodMetricTile(title: "Shifts", value: "\(summary.shiftCount)", accent: accent)
            PayPeriodMetricTile(title: "Effective Rate", value: summary.effectiveHourlyRate.asHourlyRate, accent: accent)
            PayPeriodMetricTile(title: "Best Shift", value: summary.bestShiftGross.asCurrency, accent: accent)
        }
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

private extension PayPeriodSummary {
    func displayAmount(for mode: EarningsDisplayMode) -> Double {
        mode == .gross ? grossEarnings : estimatedTakeHome
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
