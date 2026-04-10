import Foundation

private struct FederalTaxBracket {
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
        let annualizedGrossIncome = annualizedGrossIncome(
            currentGross: currentGross,
            yearToDateGrossExcludingCurrentShift: yearToDateGrossExcludingCurrentShift,
            currentHourlyRate: currentHourlyRate,
            templates: templates,
            today: today,
            calendar: calendar,
            fallbackExpectedWeeklyHours: taxProfile.expectedWeeklyHours
        )
        let annualExtraWithholding = annualExtraWithholding(
            payFrequency: payFrequency,
            taxProfile: taxProfile
        )

        return estimate(
            currentGross: currentGross,
            annualizedGrossIncome: annualizedGrossIncome,
            annualExtraWithholding: annualExtraWithholding,
            taxProfile: taxProfile
        )
    }

    static func estimate(
        currentGross: Double,
        annualizedGrossIncome: Double,
        annualExtraWithholding: Double,
        taxProfile: TaxProfile
    ) -> TaxEstimate {
        let pretaxDeductions = taxProfile.annualPretaxInsurance + taxProfile.annualRetirementContribution
        let standardDeduction = taxProfile.usesStandardDeduction ? standardDeduction(for: taxProfile.filingStatus) : 0
        let taxableIncome = max(0, annualizedGrossIncome - pretaxDeductions - standardDeduction)
        let federalTax = federalIncomeTax(for: taxableIncome, status: taxProfile.filingStatus)
        let coloradoTax = taxableIncome * SharedConstants.coloradoFlatTaxRate
        let socialSecurityTax = min(annualizedGrossIncome, 184_500) * 0.062
        let medicareTax = annualizedGrossIncome * 0.0145 + additionalMedicareTax(for: annualizedGrossIncome, status: taxProfile.filingStatus)
        let annualizedTaxes = federalTax + coloradoTax + socialSecurityTax + medicareTax + annualExtraWithholding
        let withholdingRate = annualizedGrossIncome > 0 ? annualizedTaxes / annualizedGrossIncome : 0

        return TaxEstimate(
            annualizedGrossIncome: annualizedGrossIncome,
            estimatedWithholdingRate: withholdingRate,
            currentShiftNetEstimate: max(0, currentGross * (1 - withholdingRate))
        )
    }

    static func estimatedTakeHome(for gross: Double, estimate: TaxEstimate) -> Double {
        max(0, gross * (1 - estimate.estimatedWithholdingRate))
    }

    static func estimatedTakeHome(
        for shift: ShiftRecord,
        allShifts: [ShiftRecord],
        payRates: [PayRateSchedule],
        paySchedules: [PaySchedule],
        templates: [ScheduleTemplate],
        taxProfile: TaxProfile,
        calendar: Calendar = .current
    ) -> Double {
        guard let jobIdentifier = shift.job?.id,
              let paySchedule = paySchedules.first(where: { $0.job?.id == jobIdentifier }) else {
            return shift.grossEarnings
        }

        let jobPayRates = payRates.filter { $0.job?.id == jobIdentifier }
        let jobTemplates = templates.filter { $0.job?.id == jobIdentifier }
        let currentRate = jobPayRates.isEmpty
            ? shift.effectiveRateAtClockOut
            : EarningsEngine.payRate(at: shift.endDate, payRates: jobPayRates)
        let yearToDateGross = AggregationService.totalGross(for: allShifts.filter {
            $0.id != shift.id &&
            $0.job?.id == jobIdentifier &&
            calendar.isDate($0.startDate, equalTo: shift.startDate, toGranularity: .year)
        })

        let estimate = estimate(
            currentGross: 0,
            yearToDateGrossExcludingCurrentShift: yearToDateGross,
            payFrequency: paySchedule.frequency,
            taxProfile: taxProfile,
            currentHourlyRate: currentRate,
            templates: jobTemplates,
            today: shift.endDate,
            calendar: calendar
        )

        return estimatedTakeHome(for: shift.grossEarnings, estimate: estimate)
    }

    static func annualizedGrossIncome(
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

    static func annualExtraWithholding(
        payFrequency: PayFrequency,
        taxProfile: TaxProfile
    ) -> Double {
        (taxProfile.extraFederalWithholdingPerPeriod + taxProfile.extraStateWithholdingPerPeriod)
            * payFrequency.periodsPerYear
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
                .init(baseTax: 0, lowerBound: 0, rate: 0.10),
                .init(baseTax: 1_240, lowerBound: 12_400, rate: 0.12),
                .init(baseTax: 5_800, lowerBound: 50_400, rate: 0.22),
                .init(baseTax: 17_966, lowerBound: 105_700, rate: 0.24),
                .init(baseTax: 41_024, lowerBound: 201_775, rate: 0.32),
                .init(baseTax: 58_448, lowerBound: 256_225, rate: 0.35),
                .init(baseTax: 192_979.25, lowerBound: 640_600, rate: 0.37),
            ]
        case .headOfHousehold:
            return [
                .init(baseTax: 0, lowerBound: 0, rate: 0.10),
                .init(baseTax: 1_770, lowerBound: 17_700, rate: 0.12),
                .init(baseTax: 7_740, lowerBound: 67_450, rate: 0.22),
                .init(baseTax: 16_155, lowerBound: 105_700, rate: 0.24),
                .init(baseTax: 39_207, lowerBound: 201_750, rate: 0.32),
                .init(baseTax: 56_631, lowerBound: 256_200, rate: 0.35),
                .init(baseTax: 191_171, lowerBound: 640_600, rate: 0.37),
            ]
        case .marriedFilingJointly:
            return [
                .init(baseTax: 0, lowerBound: 0, rate: 0.10),
                .init(baseTax: 2_480, lowerBound: 24_800, rate: 0.12),
                .init(baseTax: 11_600, lowerBound: 100_800, rate: 0.22),
                .init(baseTax: 35_932, lowerBound: 211_400, rate: 0.24),
                .init(baseTax: 82_048, lowerBound: 403_550, rate: 0.32),
                .init(baseTax: 116_896, lowerBound: 512_450, rate: 0.35),
                .init(baseTax: 206_583.50, lowerBound: 768_700, rate: 0.37),
            ]
        case .marriedFilingSeparately:
            return [
                .init(baseTax: 0, lowerBound: 0, rate: 0.10),
                .init(baseTax: 1_240, lowerBound: 12_400, rate: 0.12),
                .init(baseTax: 5_800, lowerBound: 50_400, rate: 0.22),
                .init(baseTax: 17_966, lowerBound: 105_700, rate: 0.24),
                .init(baseTax: 41_024, lowerBound: 201_775, rate: 0.32),
                .init(baseTax: 58_448, lowerBound: 256_225, rate: 0.35),
                .init(baseTax: 103_291.75, lowerBound: 384_350, rate: 0.37),
            ]
        }
    }
}
