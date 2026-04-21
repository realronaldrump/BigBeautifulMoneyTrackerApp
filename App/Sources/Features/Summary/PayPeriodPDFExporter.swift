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
        let margin: CGFloat = 44
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)

        try renderer.writePDF(to: url) { context in
            context.beginPage()
            var y = margin

            func ensureSpace(_ height: CGFloat) {
                if y + height > pageBounds.height - margin {
                    context.beginPage()
                    y = margin
                }
            }

            func drawText(
                _ text: String,
                font: UIFont,
                color: UIColor = .label,
                x: CGFloat = margin,
                width: CGFloat = pageBounds.width - margin * 2,
                lineHeight: CGFloat? = nil
            ) {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
                let attributed = NSAttributedString(string: text, attributes: attributes)
                let measured = attributed.boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                let height = ceil(lineHeight ?? measured.height)
                ensureSpace(height)
                attributed.draw(in: CGRect(x: x, y: y, width: width, height: height))
                y += height
            }

            func drawRule(spacing: CGFloat = 14) {
                ensureSpace(spacing + 1)
                y += spacing / 2
                UIColor.separator.setStroke()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: y))
                path.addLine(to: CGPoint(x: pageBounds.width - margin, y: y))
                path.lineWidth = 1
                path.stroke()
                y += spacing / 2
            }

            func drawMetric(_ label: String, _ value: String, column: Int, rowTop: CGFloat) {
                let columnWidth = (pageBounds.width - margin * 2 - 18) / 2
                let x = margin + CGFloat(column) * (columnWidth + 18)
                drawFixedText(label.uppercased(), font: .systemFont(ofSize: 9, weight: .semibold), color: .secondaryLabel, rect: CGRect(x: x, y: rowTop, width: columnWidth, height: 14))
                drawFixedText(value, font: .systemFont(ofSize: 16, weight: .bold), color: .label, rect: CGRect(x: x, y: rowTop + 17, width: columnWidth, height: 22))
            }

            func drawFixedText(_ text: String, font: UIFont, color: UIColor, rect: CGRect) {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byTruncatingTail
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
                NSAttributedString(string: text, attributes: attributes).draw(in: rect)
            }

            drawText("Davis's Big Beautiful Money Tracker App", font: .systemFont(ofSize: 18, weight: .bold))
            y += 6
            drawText("Estimated personal pay summary", font: .systemFont(ofSize: 13, weight: .semibold), color: .secondaryLabel)
            y += 18
            drawText(summary.jobName, font: .systemFont(ofSize: 30, weight: .heavy))
            y += 6
            drawText(summary.interval.pdfDisplayRange, font: .systemFont(ofSize: 15, weight: .medium), color: .secondaryLabel)
            y += 6
            drawText("Generated \(generatedAt.formatted(date: .abbreviated, time: .shortened))", font: .systemFont(ofSize: 11, weight: .regular), color: .tertiaryLabel)

            drawRule(spacing: 24)

            let metricRows: [(String, String)] = [
                ("Gross", summary.grossEarnings.pdfCurrency),
                ("Estimated Take-Home", summary.estimatedTakeHome.pdfCurrency),
                ("Hours", summary.totalHours.pdfHours),
                ("Shifts", "\(summary.shiftCount)"),
                ("Effective Rate", summary.effectiveHourlyRate.pdfCurrency + "/hr"),
                ("Best Shift", summary.bestShiftGross.pdfCurrency)
            ]

            for row in stride(from: 0, to: metricRows.count, by: 2) {
                ensureSpace(52)
                let rowTop = y
                drawMetric(metricRows[row].0, metricRows[row].1, column: 0, rowTop: rowTop)
                if row + 1 < metricRows.count {
                    drawMetric(metricRows[row + 1].0, metricRows[row + 1].1, column: 1, rowTop: rowTop)
                }
                y += 52
            }

            drawRule(spacing: 18)
            drawText("Breakdown", font: .systemFont(ofSize: 16, weight: .bold))
            y += 8

            let breakdownRows: [(String, String)] = [
                ("Base Earnings", summary.baseEarnings.pdfCurrency),
                ("Night Premium", summary.nightPremiumEarnings.pdfCurrency),
                ("Overtime Premium", summary.overtimePremiumEarnings.pdfCurrency),
                ("Regular Hours", summary.regularHours.pdfHours),
                ("Night Hours", summary.nightHours.pdfHours),
                ("Overtime Hours", summary.overtimeHours.pdfHours)
            ]
            for row in breakdownRows {
                ensureSpace(24)
                drawFixedText(row.0, font: .systemFont(ofSize: 12, weight: .regular), color: .secondaryLabel, rect: CGRect(x: margin, y: y, width: 260, height: 18))
                drawFixedText(row.1, font: .systemFont(ofSize: 12, weight: .semibold), color: .label, rect: CGRect(x: pageBounds.width - margin - 180, y: y, width: 180, height: 18))
                y += 24
            }

            drawRule(spacing: 18)
            drawText("Included Shifts", font: .systemFont(ofSize: 16, weight: .bold))
            y += 8

            if summary.shifts.isEmpty {
                drawText("No shifts were tracked in this period.", font: .systemFont(ofSize: 12, weight: .regular), color: .secondaryLabel)
            } else {
                for shift in summary.shifts.sorted(by: { $0.allocatedStartDate < $1.allocatedStartDate }) {
                    ensureSpace(46)
                    drawFixedText(
                        shift.allocatedStartDate.formatted(date: .abbreviated, time: .omitted),
                        font: .systemFont(ofSize: 11, weight: .semibold),
                        color: .label,
                        rect: CGRect(x: margin, y: y, width: 92, height: 16)
                    )
                    drawFixedText(
                        "\(shift.allocatedStartDate.formatted(date: .omitted, time: .shortened)) - \(shift.allocatedEndDate.formatted(date: .omitted, time: .shortened))",
                        font: .systemFont(ofSize: 11, weight: .regular),
                        color: .secondaryLabel,
                        rect: CGRect(x: margin + 98, y: y, width: 138, height: 16)
                    )
                    drawFixedText(
                        shift.totalHours.pdfHours,
                        font: .systemFont(ofSize: 11, weight: .regular),
                        color: .secondaryLabel,
                        rect: CGRect(x: margin + 242, y: y, width: 64, height: 16)
                    )
                    drawFixedText(
                        shift.grossEarnings.pdfCurrency,
                        font: .systemFont(ofSize: 11, weight: .semibold),
                        color: .label,
                        rect: CGRect(x: pageBounds.width - margin - 88, y: y, width: 88, height: 16)
                    )
                    y += 18

                    if !shift.note.isEmpty || shift.isPartial || shift.isActive || summary.isCombined {
                        let tags = [
                            summary.isCombined ? shift.jobName : nil,
                            shift.isPartial ? "Partial period allocation" : nil,
                            shift.isActive ? "Active shift" : nil,
                            shift.note.isEmpty ? nil : shift.note
                        ]
                            .compactMap { $0 }
                            .joined(separator: " • ")
                        drawFixedText(
                            tags,
                            font: .systemFont(ofSize: 9, weight: .regular),
                            color: .tertiaryLabel,
                            rect: CGRect(x: margin + 98, y: y, width: pageBounds.width - margin * 2 - 98, height: 14)
                        )
                        y += 16
                    }
                    y += 10
                }
            }

            drawRule(spacing: 18)
            drawText(
                "This PDF is generated from personal shift tracking data and estimated tax settings. It is not an employer-issued pay stub.",
                font: .systemFont(ofSize: 10, weight: .regular),
                color: .secondaryLabel
            )
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
        return "MoneyTracker-\(safeJobName.isEmpty ? "PaySummary" : safeJobName)-\(start)-\(end).pdf"
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
