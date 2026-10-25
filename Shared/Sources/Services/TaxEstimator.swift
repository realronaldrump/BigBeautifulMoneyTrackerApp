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
            taxProfile: taxProfile,
            payFrequency: payFrequency
        )
    }

    static func estimate(
        currentGross: Double,
        currentTaxableSupplemental: Double = 0,
        annualizedGrossIncome: Double,
        annualizedTaxableSupplementalIncome: Double = 0,
        annualExtraWithholding: Double,
        taxProfile: TaxProfile,
        payFrequency: PayFrequency? = nil
    ) -> TaxEstimate {
        let resolvedAnnualizedGrossIncome = max(0, annualizedGrossIncome + annualizedTaxableSupplementalIncome)
        let insurance = min(resolvedAnnualizedGrossIncome, max(0, taxProfile.annualPretaxInsurance))
        let retirement = min(resolvedAnnualizedGrossIncome - insurance, max(0, taxProfile.annualRetirementContribution))
        let pretaxDeductions = insurance + retirement
        let standardDeduction = taxProfile.usesStandardDeduction ? standardDeduction(for: taxProfile.filingStatus) : 0
        let federalTaxableIncome = max(0, resolvedAnnualizedGrossIncome - pretaxDeductions - standardDeduction)
        let coloradoTaxableIncome = max(
            0,
            resolvedAnnualizedGrossIncome
                - pretaxDeductions
                - taxProfile.coloradoAnnualWithholdingAllowance
        )
        let federalTax = federalIncomeTax(for: federalTaxableIncome, status: taxProfile.filingStatus)
        let coloradoTax = coloradoIncomeTax(
            for: coloradoTaxableIncome,
            payFrequency: payFrequency,
            roundsToWholeDollars: taxProfile.roundsColoradoWithholdingToWholeDollars
        )
        // Section 125 insurance reduces FICA wages; traditional retirement
        // deferrals reduce income-tax wages but remain subject to FICA (IRS Pub. 15).
        let ficaWages = max(0, resolvedAnnualizedGrossIncome - insurance)
        let socialSecurityTax = taxProfile.includesSocialSecurityWithholding
            ? min(ficaWages, 184_500) * 0.062
            : 0
        let medicareTax = ficaWages * 0.0145 + max(0, ficaWages - 200_000) * 0.009
        let annualizedTaxes = max(0, federalTax + coloradoTax + annualExtraWithholding) + socialSecurityTax + medicareTax
        let withholdingRate = resolvedAnnualizedGrossIncome > 0 ? min(1, annualizedTaxes / resolvedAnnualizedGrossIncome) : 0
        let deductionRate = resolvedAnnualizedGrossIncome > 0 ? pretaxDeductions / resolvedAnnualizedGrossIncome : 0

        return TaxEstimate(
            annualizedGrossIncome: resolvedAnnualizedGrossIncome,
            estimatedWithholdingRate: withholdingRate,
            currentShiftNetEstimate: max(0, (currentGross + currentTaxableSupplemental) * (1 - withholdingRate - deductionRate)),
            estimatedPayrollDeductionRate: deductionRate
        )
    }

    static func estimatedTakeHome(for gross: Double, estimate: TaxEstimate) -> Double {
        max(0, gross * estimate.estimatedNetRate)
    }

    static func effectiveTakeHome(
        for gross: Double,
        taxableSupplemental: Double,
        nonTaxableSupplemental: Double,
        estimate: TaxEstimate
    ) -> Double {
        estimatedTakeHome(for: gross + taxableSupplemental, estimate: estimate) + nonTaxableSupplemental
    }

    static func paycheckAnnualizedGross(periodGross: Double, payFrequency: PayFrequency) -> Double {
        max(0, periodGross) * payFrequency.periodsPerYear
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
            $0.endDate <= shift.startDate &&
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

    private static func coloradoIncomeTax(
        for annualizedTaxableWages: Double,
        payFrequency: PayFrequency?,
        roundsToWholeDollars: Bool
    ) -> Double {
        let annualTax = annualizedTaxableWages * SharedConstants.coloradoFlatTaxRate

        guard roundsToWholeDollars,
              let periodsPerYear = payFrequency?.periodsPerYear,
              periodsPerYear > 0
        else {
            return annualTax
        }

        return (annualTax / periodsPerYear).rounded() * periodsPerYear
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
