import Foundation
import UIKit

enum PayPeriodPDFExporter {
    static func export(
        summary: PayPeriodSummary,
        generatedAt: Date = .now,
        fileManager: FileManager = .default
    ) throws -> URL {
        let directory = fileManager.temporaryDirectory.appending(path: "MoneyTrackerPaySummaries", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appending(path: fileName(for: summary), directoryHint: .notDirectory)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let palette = PayPeriodPDFPalette(summary: summary)

        try renderer.writePDF(to: url) { context in
            let canvas = PayPeriodPDFCanvas(
                context: context,
                pageBounds: pageBounds,
                summary: summary,
                generatedAt: generatedAt,
                palette: palette
            )

            let snapshotMetrics: [(String, String, UIColor)] = summary.isSupplementOnly
                ? [
                    (summary.displayMetricTitle(for: .gross), summary.displayGrossAmount.pdfCurrency, palette.grossAccent),
                    (summary.displayMetricTitle(for: .takeHome), summary.displayTakeHomeAmount.pdfCurrency, palette.takeHomeAccent),
                    ("Supplement Total", summary.supplementalTotal.pdfCurrency, palette.accent),
                    ("Taxable Portion", summary.supplementalTaxableTotal.pdfCurrency, palette.roseAccent),
                    ("Non-Taxable Portion", summary.supplementalNonTaxableTotal.pdfCurrency, palette.complementaryAccent),
                    ("Supplements", summary.supplementMetricLabel, palette.accent),
                ]
                : [
                    (summary.displayMetricTitle(for: .gross), summary.displayGrossAmount.pdfCurrency, palette.grossAccent),
                    (summary.displayMetricTitle(for: .takeHome), summary.displayTakeHomeAmount.pdfCurrency, palette.takeHomeAccent),
                    ("Hours", summary.totalHours.pdfHours, palette.accent),
                    ("Shifts", "\(summary.shiftCount)", palette.roseAccent),
                    ("Effective Rate", summary.displayHourlyRate.map { $0.pdfCurrency + "/hr" } ?? "Unavailable", palette.complementaryAccent),
                    ("Best Shift", summary.bestShiftGross.pdfCurrency, palette.accent),
                ]

            canvas.beginPage(compact: false)
            canvas.drawMetricGrid(snapshotMetrics)

            canvas.drawKeyValueSection(
                title: "Breakdown",
                subtitle: "Where this pay-period estimate comes from.",
                rows: [
                    ("Base Earnings", summary.baseEarnings.pdfCurrency),
                    ("Night Premium", summary.nightPremiumEarnings.pdfCurrency),
                    ("Overtime Premium", summary.overtimePremiumEarnings.pdfCurrency),
                    ("Regular Hours", summary.regularHours.pdfHours),
                    ("Night Hours", summary.nightHours.pdfHours),
                    ("Overtime Hours", summary.overtimeHours.pdfHours)
                ]
            )

            if summary.supplementalTotal > 0.000_001 || !summary.supplementAllocations.isEmpty {
                let supplementalRows = summary.supplementAllocations.isEmpty
                    ? [("Supplements in This Period", summary.supplementalTotal.pdfCurrency)]
                    : summary.supplementAllocations.map { allocation in
                        let label = summary.isCombined
                            ? "\(allocation.jobName) • \(allocation.label)"
                            : allocation.label
                        return (label, allocation.amount.pdfCurrency)
                    }

                canvas.drawKeyValueSection(
                    title: "Supplemental Compensation",
                    subtitle: "Recurring non-shift compensation allocated into this period.",
                    rows: supplementalRows + [
                        ("Taxable Portion", summary.supplementalTaxableTotal.pdfCurrency),
                        ("Non-Taxable Portion", summary.supplementalNonTaxableTotal.pdfCurrency),
                        ("Supplement Total", summary.supplementalTotal.pdfCurrency)
                    ]
                )

                canvas.drawKeyValueSection(
                    title: "Effective Earnings",
                    subtitle: "Shift earnings plus supplemental compensation for this period.",
                    rows: [
                        ("Effective Gross", summary.effectiveGross.pdfCurrency),
                        ("Effective Take-Home", summary.effectiveTakeHome.pdfCurrency),
                        (
                            "Effective Hourly Rate",
                            summary.effectiveSupplementalHourlyRate.map { $0.pdfCurrency + "/hr" } ?? "Unavailable"
                        )
                    ]
                )
            }

            canvas.drawKeyValueSection(
                title: "Period Context",
                subtitle: "Extra context for planning and review.",
                rows: [
                    ("Pay Frequency", summary.frequency.title),
                    ("Status", summary.status.title),
                    ("Average Shift Gross", summary.averageShiftGross.pdfCurrency),
                    ("Annualized Gross", summary.annualizedGrossIncome.pdfCurrency),
                    ("YTD Gross Before Period", summary.yearToDateGrossBeforePeriod.pdfCurrency)
                ]
            )

            canvas.drawShiftSection(summary.shifts)
            canvas.drawDisclaimer("This PDF is generated from personal shift tracking data and estimated tax settings. It is not an employer-issued pay stub.")
        }

        return url
    }

    private static func fileName(for summary: PayPeriodSummary) -> String {
        let safeJobName = summary.jobName
            .unicodeScalars
            .map { scalar -> Character in
                CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
            }
            .reduce(into: "") { $0.append($1) }
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        let start = formatter.string(from: summary.interval.start)
        let endDisplay = Calendar.current.date(byAdding: .day, value: -1, to: summary.interval.end) ?? summary.interval.end
        let end = formatter.string(from: endDisplay)
        return "BigBeautifulSummary-\(safeJobName.isEmpty ? "PayPeriod" : safeJobName)-\(start)-\(end).pdf"
    }
}

private struct PayPeriodPDFPalette {
    let pageBackground = UIColor(red: 0.03, green: 0.04, blue: 0.05, alpha: 1)
    let pageSecondaryBackground = UIColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1)
    let surface = UIColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 0.98)
    let raisedSurface = UIColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 0.98)
    let ink = UIColor.white
    let mutedInk = UIColor.white.withAlphaComponent(0.72)
    let subtleInk = UIColor.white.withAlphaComponent(0.48)
    let border = UIColor.white.withAlphaComponent(0.08)
    let innerHighlight = UIColor.white.withAlphaComponent(0.18)
    let headerFill = UIColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 0.98)
    let headerSecondaryFill = UIColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 0.98)
    let inverseInk = UIColor.white
    let grossAccent = UIColor(red: 0.30, green: 0.94, blue: 0.62, alpha: 1)
    let takeHomeAccent = UIColor(red: 0.95, green: 0.78, blue: 0.38, alpha: 1)
    let roseAccent = UIColor(red: 0.90, green: 0.48, blue: 0.60, alpha: 1)
    let accent: UIColor
    let accentSoft: UIColor
    let accentMuted: UIColor
    let complementaryAccent: UIColor

    init(summary: PayPeriodSummary) {
        let baseAccent: UIColor = switch summary.accent {
        case .emerald:
            UIColor(red: 0.227, green: 0.749, blue: 0.506, alpha: 1)
        case .sky:
            UIColor(red: 0.298, green: 0.620, blue: 0.914, alpha: 1)
        case .amber:
            UIColor(red: 0.902, green: 0.639, blue: 0.188, alpha: 1)
        case .coral:
            UIColor(red: 0.906, green: 0.416, blue: 0.345, alpha: 1)
        case .rose:
            UIColor(red: 0.824, green: 0.353, blue: 0.522, alpha: 1)
        case .slate:
            UIColor(red: 0.455, green: 0.533, blue: 0.663, alpha: 1)
        }

        accent = summary.isCombined ? grossAccent : baseAccent
        complementaryAccent = switch summary.accent {
        case .amber:
            grossAccent
        case .coral, .rose:
            takeHomeAccent
        default:
            takeHomeAccent
        }
        accentSoft = accent.withAlphaComponent(0.16)
        accentMuted = accent.withAlphaComponent(0.74)
    }
}

private final class PayPeriodPDFCanvas {
    private let context: UIGraphicsPDFRendererContext
    private let pageBounds: CGRect
    private let summary: PayPeriodSummary
    private let generatedAt: Date
    private let palette: PayPeriodPDFPalette
    private let margin: CGFloat = 36
    private let footerHeight: CGFloat = 24
    private let sectionTitleHeight: CGFloat = 34
    private let sectionSpacing: CGFloat = 20

    private var y: CGFloat = 0
    private var pageNumber = 0

    init(
        context: UIGraphicsPDFRendererContext,
        pageBounds: CGRect,
        summary: PayPeriodSummary,
        generatedAt: Date,
        palette: PayPeriodPDFPalette
    ) {
        self.context = context
        self.pageBounds = pageBounds
        self.summary = summary
        self.generatedAt = generatedAt
        self.palette = palette
    }

    private var contentWidth: CGFloat {
        pageBounds.width - margin * 2
    }

    private var contentBottom: CGFloat {
        pageBounds.height - margin - footerHeight
    }

    func beginPage(compact: Bool) {
        context.beginPage()
        pageNumber += 1

        drawPageBackground()

        drawFooter()
        drawHeader(compact: compact)
        y = margin + (compact ? 78 : 154)
    }

    func drawMetricGrid(_ items: [(String, String, UIColor)]) {
        let columns = 2
        let spacing: CGFloat = 14
        let cardHeight: CGFloat = 76
        let columnWidth = (contentWidth - spacing) / CGFloat(columns)
        let initialBodyHeight = items.isEmpty ? sectionSpacing : (cardHeight + sectionSpacing)

        beginSection(
            title: "Snapshot",
            subtitle: "Primary numbers for this pay period.",
            minimumBodyHeight: initialBodyHeight
        )

        for index in items.indices {
            let row = index / columns
            let column = index % columns
            let requiredHeight = CGFloat(row + 1) * cardHeight + CGFloat(row) * spacing
            ensureSpace(requiredHeight + sectionSpacing) { canvas in
                canvas.drawSectionTitle("Snapshot", subtitle: "Primary numbers for this pay period.")
            }

            let rect = CGRect(
                x: margin + CGFloat(column) * (columnWidth + spacing),
                y: y + CGFloat(row) * (cardHeight + spacing),
                width: columnWidth,
                height: cardHeight
            )
            drawRoundedCard(rect, fill: palette.surface, stroke: items[index].2)
            drawText(
                items[index].0.uppercased(),
                font: .systemFont(ofSize: 10, weight: .semibold),
                color: items[index].2.withAlphaComponent(0.82),
                rect: rect.insetBy(dx: 16, dy: 14),
                tracking: 1.0
            )
            drawText(
                items[index].1,
                font: .systemFont(ofSize: 20, weight: .bold),
                color: items[index].2,
                rect: CGRect(
                    x: rect.minX + 16,
                    y: rect.minY + 32,
                    width: rect.width - 32,
                    height: 26
                )
            )
        }

        let rows = Int(ceil(Double(items.count) / Double(columns)))
        y += CGFloat(rows) * cardHeight + CGFloat(max(0, rows - 1)) * spacing + sectionSpacing
    }

    func drawKeyValueSection(title: String, subtitle: String, rows: [(String, String)]) {
        let rowHeight: CGFloat = 24
        let innerPadding: CGFloat = 18
        let boxHeight = innerPadding * 2 + CGFloat(rows.count) * rowHeight + CGFloat(max(0, rows.count - 1)) * 10

        beginSection(
            title: title,
            subtitle: subtitle,
            minimumBodyHeight: boxHeight + sectionSpacing
        )

        let rect = CGRect(x: margin, y: y, width: contentWidth, height: boxHeight)
        drawRoundedCard(rect, fill: palette.surface, stroke: palette.accent)

        var rowY = rect.minY + innerPadding
        for (index, row) in rows.enumerated() {
            drawText(
                row.0,
                font: .systemFont(ofSize: 12, weight: .medium),
                color: palette.mutedInk,
                rect: CGRect(x: rect.minX + 18, y: rowY, width: rect.width * 0.55, height: rowHeight)
            )
            drawText(
                row.1,
                font: .systemFont(ofSize: 12, weight: .bold),
                color: palette.ink,
                rect: CGRect(x: rect.maxX - 220, y: rowY, width: 200, height: rowHeight),
                alignment: .right
            )

            rowY += rowHeight
            if index < rows.count - 1 {
                let dividerY = rowY + 4
                let divider = UIBezierPath()
                divider.move(to: CGPoint(x: rect.minX + 18, y: dividerY))
                divider.addLine(to: CGPoint(x: rect.maxX - 18, y: dividerY))
                palette.border.setStroke()
                divider.lineWidth = 1
                divider.stroke()
                rowY += 10
            }
        }

        y = rect.maxY + sectionSpacing
    }

    func drawShiftSection(_ shifts: [PayPeriodShiftSummary]) {
        let sortedShifts = shifts.sorted(by: { $0.allocatedStartDate < $1.allocatedStartDate })
        let firstRowHeight = sortedShifts.first.map { shift -> CGFloat in
            shiftTags(for: shift).isEmpty ? 72 : 92
        } ?? 72
        let initialBodyHeight = sortedShifts.isEmpty
            ? (72 + sectionSpacing)
            : (firstRowHeight + 10 + sectionSpacing)

        beginSection(
            title: "Included Shifts",
            subtitle: "Entries that contribute to this estimate.",
            minimumBodyHeight: initialBodyHeight
        )

        if sortedShifts.isEmpty {
            let rect = CGRect(x: margin, y: y, width: contentWidth, height: 72)
            drawRoundedCard(rect, fill: palette.surface, stroke: palette.accent)
            drawText(
                "No shifts were tracked in this period.",
                font: .systemFont(ofSize: 12, weight: .medium),
                color: palette.mutedInk,
                rect: rect.insetBy(dx: 18, dy: 22)
            )
            y = rect.maxY + sectionSpacing
            return
        }

        for shift in sortedShifts {
            let tags = shiftTags(for: shift)
            let rowHeight: CGFloat = tags.isEmpty ? 72 : 92
            ensureSpace(rowHeight + 10 + sectionSpacing) { canvas in
                canvas.drawSectionTitle("Included Shifts", subtitle: "Entries that contribute to this estimate.")
            }

            let rect = CGRect(x: margin, y: y, width: contentWidth, height: rowHeight)
            drawRoundedCard(rect, fill: palette.surface, stroke: shift.isActive ? palette.grossAccent : palette.accent)

            let dateBadge = CGRect(x: rect.minX + 16, y: rect.minY + 14, width: 84, height: 42)
            drawRoundedCard(dateBadge, fill: palette.raisedSurface, stroke: palette.takeHomeAccent)
            drawText(
                shift.allocatedStartDate.formatted(.dateTime.month(.abbreviated)),
                font: .systemFont(ofSize: 10, weight: .semibold),
                color: palette.accentMuted,
                rect: CGRect(x: dateBadge.minX, y: dateBadge.minY + 6, width: dateBadge.width, height: 12),
                alignment: .center,
                tracking: 0.8
            )
            drawText(
                shift.allocatedStartDate.formatted(.dateTime.day()),
                font: .systemFont(ofSize: 18, weight: .bold),
                color: palette.ink,
                rect: CGRect(x: dateBadge.minX, y: dateBadge.minY + 18, width: dateBadge.width, height: 18),
                alignment: .center
            )

            let detailX = dateBadge.maxX + 14
            let detailWidth = rect.width - 240
            drawText(
                shift.jobName,
                font: .systemFont(ofSize: 12, weight: .semibold),
                color: palette.accentMuted,
                rect: CGRect(x: detailX, y: rect.minY + 14, width: detailWidth, height: 16)
            )
            drawText(
                "\(shift.allocatedStartDate.formatted(date: .abbreviated, time: .omitted)) • \(shift.allocatedStartDate.formatted(date: .omitted, time: .shortened)) - \(shift.allocatedEndDate.formatted(date: .omitted, time: .shortened))",
                font: .systemFont(ofSize: 12, weight: .semibold),
                color: palette.ink,
                rect: CGRect(x: detailX, y: rect.minY + 32, width: detailWidth, height: 16)
            )
            drawText(
                shift.totalHours.pdfHours,
                font: .systemFont(ofSize: 11, weight: .medium),
                color: palette.mutedInk,
                rect: CGRect(x: rect.maxX - 150, y: rect.minY + 20, width: 124, height: 16),
                alignment: .right
            )
            drawText(
                shift.grossEarnings.pdfCurrency,
                font: .systemFont(ofSize: 16, weight: .bold),
                color: palette.grossAccent,
                rect: CGRect(x: rect.maxX - 170, y: rect.minY + 38, width: 144, height: 20),
                alignment: .right
            )

            if !tags.isEmpty {
                drawText(
                    tags,
                    font: .systemFont(ofSize: 10, weight: .medium),
                    color: palette.subtleInk,
                    rect: CGRect(x: detailX, y: rect.minY + 58, width: rect.width - 128, height: 24)
                )
            }

            y = rect.maxY + 10
        }

        y += sectionSpacing - 10
    }

    func drawDisclaimer(_ text: String) {
        beginSection(
            title: "Notes",
            subtitle: "What this document is and is not.",
            minimumBodyHeight: 68 + sectionSpacing
        )
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: 68)
        drawRoundedCard(rect, fill: palette.raisedSurface, stroke: palette.roseAccent)
        drawText(
            text,
            font: .systemFont(ofSize: 10, weight: .medium),
            color: palette.mutedInk,
            rect: rect.insetBy(dx: 18, dy: 14)
        )
        y = rect.maxY + sectionSpacing
    }

    private func drawHeader(compact: Bool) {
        let headerRect = CGRect(x: margin, y: margin, width: contentWidth, height: compact ? 62 : 138)
        drawRoundedCard(headerRect, fill: palette.headerFill, stroke: palette.accent, cornerRadius: 28)

        if compact {
            let jobNameLayout = PayPeriodPDFTextLayout.fittedSingleLine(
                summary.jobName,
                font: .systemFont(ofSize: 18, weight: .bold),
                maxWidth: headerRect.width - 198,
                minimumPointSize: 15
            )
            drawText(
                "BIG BEAUTIFUL EXPORT",
                font: .systemFont(ofSize: 10, weight: .semibold),
                color: palette.takeHomeAccent,
                rect: CGRect(x: headerRect.minX + 18, y: headerRect.minY + 12, width: 180, height: 12),
                tracking: 1.2
            )
            drawText(
                jobNameLayout.text,
                font: jobNameLayout.font,
                color: palette.inverseInk,
                rect: CGRect(x: headerRect.minX + 18, y: headerRect.minY + 24, width: headerRect.width - 180, height: 22),
                lineBreakMode: .byTruncatingTail
            )
            drawText(
                summary.interval.pdfDisplayRange,
                font: .systemFont(ofSize: 11, weight: .medium),
                color: palette.inverseInk.withAlphaComponent(0.78),
                rect: CGRect(x: headerRect.minX + 18, y: headerRect.minY + 44, width: headerRect.width - 180, height: 14)
            )
            return
        }

        let summaryPanel = CGRect(x: headerRect.maxX - 178, y: headerRect.minY + 16, width: 150, height: 92)
        drawRoundedCard(summaryPanel, fill: palette.headerSecondaryFill, stroke: palette.takeHomeAccent)
        let jobNameLayout = PayPeriodPDFTextLayout.fittedSingleLine(
            summary.jobName,
            font: .systemFont(ofSize: 28, weight: .heavy),
            maxWidth: headerRect.width - 228,
            minimumPointSize: 22
        )

        drawText(
            "BIG BEAUTIFUL SUMMARY",
            font: .systemFont(ofSize: 10, weight: .semibold),
            color: palette.takeHomeAccent,
            rect: CGRect(x: headerRect.minX + 22, y: headerRect.minY + 20, width: 220, height: 12),
            tracking: 1.4
        )
        drawText(
            jobNameLayout.text,
            font: jobNameLayout.font,
            color: palette.inverseInk,
            rect: CGRect(x: headerRect.minX + 22, y: headerRect.minY + 38, width: headerRect.width - 228, height: 32),
            lineBreakMode: .byTruncatingTail
        )
        drawText(
            summary.interval.pdfDisplayRange,
            font: .systemFont(ofSize: 14, weight: .semibold),
            color: palette.inverseInk.withAlphaComponent(0.88),
            rect: CGRect(x: headerRect.minX + 22, y: headerRect.minY + 74, width: headerRect.width - 228, height: 18)
        )
        drawText(
            "Generated \(generatedAt.formatted(date: .abbreviated, time: .shortened))",
            font: .systemFont(ofSize: 11, weight: .medium),
            color: palette.inverseInk.withAlphaComponent(0.68),
            rect: CGRect(x: headerRect.minX + 22, y: headerRect.minY + 96, width: headerRect.width - 228, height: 14)
        )

        drawChip(summary.frequency.title, x: headerRect.minX + 22, y: headerRect.minY + 114)
        drawChip(summary.status.title, x: headerRect.minX + 118, y: headerRect.minY + 114)

        drawText(
            summary.displayMetricTitle(for: .takeHome),
            font: .systemFont(ofSize: 10, weight: .semibold),
            color: palette.inverseInk.withAlphaComponent(0.66),
            rect: CGRect(x: summaryPanel.minX + 16, y: summaryPanel.minY + 14, width: summaryPanel.width - 32, height: 12)
        )
        drawText(
            summary.displayTakeHomeAmount.pdfCurrency,
            font: .systemFont(ofSize: 20, weight: .bold),
            color: palette.takeHomeAccent,
            rect: CGRect(x: summaryPanel.minX + 16, y: summaryPanel.minY + 28, width: summaryPanel.width - 32, height: 24)
        )
        drawText(
            "\(summary.displayMetricTitle(for: .gross)) \(summary.displayGrossAmount.pdfCurrency)",
            font: .systemFont(ofSize: 11, weight: .semibold),
            color: palette.grossAccent,
            rect: CGRect(x: summaryPanel.minX + 16, y: summaryPanel.minY + 58, width: summaryPanel.width - 32, height: 16)
        )
        drawText(
            summary.displaySummaryContext,
            font: .systemFont(ofSize: 9, weight: .medium),
            color: palette.inverseInk.withAlphaComponent(0.68),
            rect: CGRect(x: summaryPanel.minX + 16, y: summaryPanel.minY + 72, width: summaryPanel.width - 32, height: 20)
        )
    }

    private func drawFooter() {
        let footerY = pageBounds.height - margin
        let line = UIBezierPath()
        line.move(to: CGPoint(x: margin, y: footerY - 12))
        line.addLine(to: CGPoint(x: pageBounds.width - margin, y: footerY - 12))
        palette.border.setStroke()
        line.lineWidth = 1
        line.stroke()

        drawText(
            "Davis's Big Beautiful Money Tracker App",
            font: .systemFont(ofSize: 9, weight: .medium),
            color: palette.subtleInk,
            rect: CGRect(x: margin, y: footerY - 2, width: 220, height: 12)
        )
        drawText(
            "Page \(pageNumber)",
            font: .systemFont(ofSize: 9, weight: .semibold),
            color: palette.subtleInk,
            rect: CGRect(x: pageBounds.width - margin - 80, y: footerY - 2, width: 80, height: 12),
            alignment: .right
        )
    }

    private func beginSection(title: String, subtitle: String, minimumBodyHeight: CGFloat) {
        ensureSpace(sectionTitleHeight + minimumBodyHeight)
        drawSectionTitle(title, subtitle: subtitle)
    }

    private func drawSectionTitle(_ title: String, subtitle: String) {
        drawText(
            title,
            font: .systemFont(ofSize: 16, weight: .bold),
            color: palette.ink,
            rect: CGRect(x: margin, y: y, width: contentWidth, height: 18)
        )
        drawText(
            subtitle,
            font: .systemFont(ofSize: 11, weight: .medium),
            color: palette.mutedInk,
            rect: CGRect(x: margin, y: y + 18, width: contentWidth, height: 14)
        )
        y += sectionTitleHeight
    }

    private func drawChip(_ text: String, x: CGFloat, y: CGFloat) {
        let width = max(64, text.size(withAttributes: [.font: UIFont.systemFont(ofSize: 10, weight: .semibold)]).width + 24)
        let rect = CGRect(x: x, y: y, width: width, height: 18)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 9)
        palette.accent.withAlphaComponent(0.18).setFill()
        path.fill()
        palette.accent.withAlphaComponent(0.26).setStroke()
        path.lineWidth = 1
        path.stroke()
        drawText(
            text.uppercased(),
            font: .systemFont(ofSize: 9, weight: .bold),
            color: palette.inverseInk.withAlphaComponent(0.9),
            rect: rect.insetBy(dx: 8, dy: 3),
            alignment: .center,
            tracking: 0.8
        )
    }

    private func shiftTags(for shift: PayPeriodShiftSummary) -> String {
        [
            summary.isCombined ? shift.jobName : nil,
            shift.isPartial ? "Partial period allocation" : nil,
            shift.isActive ? "Active shift" : nil,
            shift.note.isEmpty ? nil : shift.note
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }

    private func ensureSpace(_ height: CGFloat, afterBreak: ((PayPeriodPDFCanvas) -> Void)? = nil) {
        guard y + height > contentBottom else {
            return
        }

        beginPage(compact: true)
        afterBreak?(self)
    }

    private func drawPageBackground() {
        drawLinearGradient(
            in: pageBounds,
            colors: [palette.pageBackground, palette.pageSecondaryBackground, palette.pageBackground],
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 1, y: 1)
        )

        drawRadialGlow(
            center: CGPoint(x: pageBounds.maxX - 96, y: pageBounds.minY + 72),
            radius: 240,
            color: palette.accent.withAlphaComponent(0.18)
        )
        drawRadialGlow(
            center: CGPoint(x: pageBounds.minX + 130, y: pageBounds.maxY - 120),
            radius: 210,
            color: palette.complementaryAccent.withAlphaComponent(0.10)
        )
        drawRadialGlow(
            center: CGPoint(x: pageBounds.minX + 88, y: pageBounds.midY + 120),
            radius: 170,
            color: palette.roseAccent.withAlphaComponent(0.07)
        )

        let highlightRect = CGRect(x: 0, y: 0, width: pageBounds.width, height: pageBounds.height)
        drawLinearGradient(
            in: highlightRect,
            colors: [
                UIColor.white.withAlphaComponent(0.06),
                UIColor.clear,
                UIColor.white.withAlphaComponent(0.03)
            ],
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 1, y: 1)
        )
    }

    private func drawRoundedCard(
        _ rect: CGRect,
        fill: UIColor,
        stroke: UIColor,
        cornerRadius: CGFloat = 20
    ) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        let cgContext = context.cgContext

        cgContext.saveGState()
        cgContext.setShadow(
            offset: CGSize(width: 0, height: 10),
            blur: 26,
            color: stroke.withAlphaComponent(0.22).cgColor
        )
        fill.setFill()
        path.fill()
        cgContext.restoreGState()

        cgContext.saveGState()
        path.addClip()
        drawLinearGradient(
            in: rect,
            colors: [fill.lightened(by: 0.04), fill, fill.darkened(by: 0.14)],
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 1, y: 1)
        )
        drawLinearGradient(
            in: rect,
            colors: [stroke.withAlphaComponent(0.10), UIColor.clear, palette.pageBackground.withAlphaComponent(0.10)],
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 1, y: 1)
        )
        drawRadialGlow(
            center: CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.minY + rect.height * 0.12),
            radius: max(rect.width, rect.height) * 0.60,
            color: stroke.withAlphaComponent(0.16)
        )
        cgContext.restoreGState()

        palette.innerHighlight.setStroke()
        path.lineWidth = 1
        path.stroke()

        let innerPath = UIBezierPath(
            roundedRect: rect.insetBy(dx: 1, dy: 1),
            cornerRadius: max(0, cornerRadius - 1)
        )
        stroke.withAlphaComponent(0.16).setStroke()
        innerPath.lineWidth = 1
        innerPath.stroke()
    }

    private func drawLinearGradient(
        in rect: CGRect,
        colors: [UIColor],
        startPoint: CGPoint,
        endPoint: CGPoint
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors.map(\.cgColor) as CFArray,
            locations: nil
        ) else {
            return
        }

        let cgContext = context.cgContext
        let start = CGPoint(x: rect.minX + (rect.width * startPoint.x), y: rect.minY + (rect.height * startPoint.y))
        let end = CGPoint(x: rect.minX + (rect.width * endPoint.x), y: rect.minY + (rect.height * endPoint.y))
        cgContext.saveGState()
        cgContext.drawLinearGradient(gradient, start: start, end: end, options: [])
        cgContext.restoreGState()
    }

    private func drawRadialGlow(center: CGPoint, radius: CGFloat, color: UIColor) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
            locations: [0, 1]
        ) else {
            return
        }

        let cgContext = context.cgContext
        cgContext.saveGState()
        cgContext.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: [.drawsAfterEndLocation]
        )
        cgContext.restoreGState()
    }

    private func drawText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        rect: CGRect,
        alignment: NSTextAlignment = .left,
        tracking: CGFloat = 0,
        lineBreakMode: NSLineBreakMode = .byWordWrapping
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lineBreakMode
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
            .kern: tracking
        ]
        NSAttributedString(string: text, attributes: attributes).draw(in: rect)
    }
}

enum PayPeriodPDFTextLayout {
    static func fittedSingleLine(
        _ text: String,
        font: UIFont,
        maxWidth: CGFloat,
        minimumPointSize: CGFloat
    ) -> (text: String, font: UIFont) {
        guard !text.isEmpty else {
            return ("", font)
        }

        var fittedFont = font
        while fittedFont.pointSize > minimumPointSize && measuredWidth(for: text, font: fittedFont) > maxWidth {
            fittedFont = fittedFont.withSize(max(minimumPointSize, fittedFont.pointSize - 1))
        }

        let fittedText = measuredWidth(for: text, font: fittedFont) > maxWidth
            ? truncatedSingleLine(text, font: fittedFont, maxWidth: maxWidth)
            : text

        return (fittedText, fittedFont)
    }

    static func measuredWidth(for text: String, font: UIFont) -> CGFloat {
        NSString(string: text).size(withAttributes: [.font: font]).width
    }

    private static func truncatedSingleLine(_ text: String, font: UIFont, maxWidth: CGFloat) -> String {
        let ellipsis = "…"
        guard measuredWidth(for: ellipsis, font: font) <= maxWidth else {
            return ellipsis
        }
        guard measuredWidth(for: text, font: font) > maxWidth else {
            return text
        }

        let characters = Array(text)
        var low = 0
        var high = characters.count
        var best = ellipsis

        while low <= high {
            let mid = (low + high) / 2
            let candidate = String(characters.prefix(mid)) + ellipsis
            if measuredWidth(for: candidate, font: font) <= maxWidth {
                best = candidate
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return best
    }
}

private extension DateInterval {
    var pdfDisplayRange: String {
        let endDisplayDate = Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end
        return "\(start.formatted(date: .long, time: .omitted)) - \(endDisplayDate.formatted(date: .long, time: .omitted))"
    }
}

private extension Double {
    var pdfCurrency: String {
        formatted(.currency(code: "USD"))
    }

    var pdfHours: String {
        formatted(.number.precision(.fractionLength(2))) + " hrs"
    }
}

private extension UIColor {
    func lightened(by amount: CGFloat) -> UIColor {
        adjusted(by: abs(amount))
    }

    func darkened(by amount: CGFloat) -> UIColor {
        adjusted(by: -abs(amount))
    }

    private func adjusted(by amount: CGFloat) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return self
        }

        return UIColor(
            red: min(max(red + amount, 0), 1),
            green: min(max(green + amount, 0), 1),
            blue: min(max(blue + amount, 0), 1),
            alpha: alpha
        )
    }
}
