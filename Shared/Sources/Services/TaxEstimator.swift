import Foundation

private struct FederalTaxBracket {
    let upperBound: Double
    let baseTax: Double
    let lowerBound: Double
    let rate: Double
}

enum TaxEstimator {
    static func estimate(
        currentGross: Double,
        yearToDateGrossExcludingCurrentShift: Double,
        payFrequency: PayFrequency,
        taxProfile: TaxProfile,
        currentHourlyRate: Double,
        templates: [ScheduleTemplate],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> TaxEstimate {
        let annualizedGrossIncome = annualizedGross(
            currentGross: currentGross,
            yearToDateGrossExcludingCurrentShift: yearToDateGrossExcludingCurrentShift,
            currentHourlyRate: currentHourlyRate,
            templates: templates,
            today: today,
            calendar: calendar,
            fallbackExpectedWeeklyHours: taxProfile.expectedWeeklyHours
        )

        let pretaxDeductions = taxProfile.annualPretaxInsurance + taxProfile.annualRetirementContribution
        let standardDeduction = taxProfile.usesStandardDeduction ? standardDeduction(for: taxProfile.filingStatus) : 0
        let taxableIncome = max(0, annualizedGrossIncome - pretaxDeductions - standardDeduction)
        let federalTax = federalIncomeTax(for: taxableIncome, status: taxProfile.filingStatus)
        let coloradoTax = taxableIncome * SharedConstants.coloradoFlatTaxRate
        let socialSecurityTax = min(annualizedGrossIncome, 184_500) * 0.062
        let medicareTax = annualizedGrossIncome * 0.0145 + additionalMedicareTax(for: annualizedGrossIncome, status: taxProfile.filingStatus)
        let extraWithholding = (taxProfile.extraFederalWithholdingPerPeriod + taxProfile.extraStateWithholdingPerPeriod) * payFrequency.periodsPerYear
        let annualizedTaxes = federalTax + coloradoTax + socialSecurityTax + medicareTax + extraWithholding
        let annualizedNetIncome = max(0, annualizedGrossIncome - annualizedTaxes)
        let withholdingRate = annualizedGrossIncome > 0 ? annualizedTaxes / annualizedGrossIncome : 0

        return TaxEstimate(
            annualizedGrossIncome: annualizedGrossIncome,
            annualizedNetIncome: annualizedNetIncome,
            estimatedWithholdingRate: withholdingRate,
            currentShiftNetEstimate: max(0, currentGross * (1 - withholdingRate))
        )
    }

    static func estimatedTakeHome(for gross: Double, estimate: TaxEstimate) -> Double {
        max(0, gross * (1 - estimate.estimatedWithholdingRate))
    }

    private static func annualizedGross(
        currentGross: Double,
        yearToDateGrossExcludingCurrentShift: Double,
        currentHourlyRate: Double,
        templates: [ScheduleTemplate],
        today: Date,
        calendar: Calendar,
        fallbackExpectedWeeklyHours: Double
    ) -> Double {
        let yearStart = calendar.date(from: DateComponents(year: calendar.component(.year, from: today), month: 1, day: 1)) ?? today
        let dayOfYear = max(1, (calendar.dateComponents([.day], from: yearStart, to: today).day ?? 0) + 1)
        let observedGross = yearToDateGrossExcludingCurrentShift + currentGross
        let observedAnnualized = observedGross > 0 ? observedGross / Double(dayOfYear) * 365 : 0

        let templateWeeklyHours = templates
            .filter(\.isEnabled)
            .reduce(0) { $0 + $1.scheduledHours }
        let templateAnnualized = templateWeeklyHours > 0 ? templateWeeklyHours * currentHourlyRate * 52 : 0
        let fallbackAnnualized = currentHourlyRate * max(fallbackExpectedWeeklyHours, 1) * 52

        if templateAnnualized > 0 && observedAnnualized > 0 {
            return max(templateAnnualized, observedAnnualized)
        }
        return max(observedAnnualized, templateAnnualized, fallbackAnnualized)
    }

    private static func standardDeduction(for status: FilingStatus) -> Double {
        switch status {
        case .single, .marriedFilingSeparately:
            16_100
        case .marriedFilingJointly:
            32_200
        case .headOfHousehold:
            24_150
        }
    }

    private static func federalIncomeTax(for taxableIncome: Double, status: FilingStatus) -> Double {
        let brackets = federalBrackets(for: status)
        guard let bracket = brackets.last(where: { taxableIncome > $0.lowerBound }) else { return 0 }
        return bracket.baseTax + (taxableIncome - bracket.lowerBound) * bracket.rate
    }

    private static func additionalMedicareTax(for income: Double, status: FilingStatus) -> Double {
        let threshold: Double
        switch status {
        case .marriedFilingJointly:
            threshold = 250_000
        case .marriedFilingSeparately:
            threshold = 125_000
        case .single, .headOfHousehold:
            threshold = 200_000
        }

        return max(0, income - threshold) * 0.009
    }

    private static func federalBrackets(for status: FilingStatus) -> [FederalTaxBracket] {
        switch status {
        case .single:
            return [
                .init(upperBound: 12_400, baseTax: 0, lowerBound: 0, rate: 0.10),
                .init(upperBound: 50_400, baseTax: 1_240, lowerBound: 12_400, rate: 0.12),
                .init(upperBound: 105_700, baseTax: 5_800, lowerBound: 50_400, rate: 0.22),
                .init(upperBound: 201_775, baseTax: 17_966, lowerBound: 105_700, rate: 0.24),
                .init(upperBound: 256_225, baseTax: 41_024, lowerBound: 201_775, rate: 0.32),
                .init(upperBound: 640_600, baseTax: 58_448, lowerBound: 256_225, rate: 0.35),
                .init(upperBound: .infinity, baseTax: 192_979.25, lowerBound: 640_600, rate: 0.37),
            ]
        case .headOfHousehold:
            return [
                .init(upperBound: 17_700, baseTax: 0, lowerBound: 0, rate: 0.10),
                .init(upperBound: 67_450, baseTax: 1_770, lowerBound: 17_700, rate: 0.12),
                .init(upperBound: 105_700, baseTax: 7_740, lowerBound: 67_450, rate: 0.22),
                .init(upperBound: 201_750, baseTax: 16_155, lowerBound: 105_700, rate: 0.24),
                .init(upperBound: 256_200, baseTax: 39_207, lowerBound: 201_750, rate: 0.32),
                .init(upperBound: 640_600, baseTax: 56_631, lowerBound: 256_200, rate: 0.35),
                .init(upperBound: .infinity, baseTax: 191_171, lowerBound: 640_600, rate: 0.37),
            ]
        case .marriedFilingJointly:
            return [
                .init(upperBound: 24_800, baseTax: 0, lowerBound: 0, rate: 0.10),
                .init(upperBound: 100_800, baseTax: 2_480, lowerBound: 24_800, rate: 0.12),
                .init(upperBound: 211_400, baseTax: 11_600, lowerBound: 100_800, rate: 0.22),
                .init(upperBound: 403_550, baseTax: 35_932, lowerBound: 211_400, rate: 0.24),
                .init(upperBound: 512_450, baseTax: 82_048, lowerBound: 403_550, rate: 0.32),
                .init(upperBound: 768_700, baseTax: 116_896, lowerBound: 512_450, rate: 0.35),
                .init(upperBound: .infinity, baseTax: 206_583.50, lowerBound: 768_700, rate: 0.37),
            ]
        case .marriedFilingSeparately:
            return [
                .init(upperBound: 12_400, baseTax: 0, lowerBound: 0, rate: 0.10),
                .init(upperBound: 50_400, baseTax: 1_240, lowerBound: 12_400, rate: 0.12),
                .init(upperBound: 105_700, baseTax: 5_800, lowerBound: 50_400, rate: 0.22),
                .init(upperBound: 201_775, baseTax: 17_966, lowerBound: 105_700, rate: 0.24),
                .init(upperBound: 256_225, baseTax: 41_024, lowerBound: 201_775, rate: 0.32),
                .init(upperBound: 384_350, baseTax: 58_448, lowerBound: 256_225, rate: 0.35),
                .init(upperBound: .infinity, baseTax: 103_291.75, lowerBound: 384_350, rate: 0.37),
            ]
        }
    }
}
