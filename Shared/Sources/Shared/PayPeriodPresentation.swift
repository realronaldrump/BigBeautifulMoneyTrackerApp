import Foundation

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
