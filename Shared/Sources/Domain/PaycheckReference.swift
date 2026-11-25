import Foundation

/// Two totals from the same check, including all employee deductions.
struct PaycheckReference: Equatable {
    let gross: Double
    let net: Double

    init?(gross: Double?, net: Double?) {
        guard let gross, let net, gross.isFinite, net.isFinite,
              gross > 0, net >= 0, net <= gross else { return nil }
        self.gross = gross
        self.net = net
    }

    var netRate: Double { net / gross }
}

/// Reads the current row of a supported text-based pay statement.
/// Reject unfamiliar layouts rather than mistaking YTD or taxable wages for gross.
struct PayStatement {
    let paycheck: PaycheckReference
    let hourlyRate: Double?
    let frequency: PayFrequency?
    let periodStart: Date?
    let paidDate: Date?

    init?(text: String, calendar: Calendar = .current) {
        let lines = text.components(separatedBy: .newlines).map {
            $0.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }.filter { !$0.isEmpty }
        let headers = lines.indices.filter { lines[$0] == "Pay Summary" }
        guard headers.count == 1, let header = headers.first,
              lines.indices.contains(header + 2),
              lines[header + 1] == "Gross FIT Taxable Wages Taxes Deductions Net Pay"
        else { return nil }

        let row = lines[header + 2].split(separator: " ")
        func dollars(_ field: Substring) -> Double? {
            guard field.first == "$" else { return nil }
            return Double(field.dropFirst().replacingOccurrences(of: ",", with: ""))
        }
        guard row.count == 6, row[0] == "Current",
              let gross = dollars(row[1]), let taxes = dollars(row[3]),
              let deductions = dollars(row[4]), let net = dollars(row[5]),
              abs(gross - taxes - deductions - net) < 0.005,
              let paycheck = PaycheckReference(gross: gross, net: net)
        else { return nil }
        self.paycheck = paycheck

        func value(after label: String) -> Substring? {
            lines.first(where: { $0.hasPrefix(label) })?.dropFirst(label.count)
        }
        let rate = value(after: "Pay Rate ").flatMap(dollars)
        hourlyRate = rate.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let frequencyText = value(after: "Pay Frequency ")?.lowercased().replacingOccurrences(of: "-", with: "")
        frequency = PayFrequency.allCases.first {
            $0.title.lowercased() == frequencyText || $0.rawValue.lowercased() == frequencyText
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MM/dd/yyyy"
        formatter.isLenient = false
        func date(after label: String) -> Date? {
            value(after: label).flatMap { formatter.date(from: String($0)) }
        }
        periodStart = date(after: "Period Start Date ")
        paidDate = date(after: "Pay Date ")
    }
}
