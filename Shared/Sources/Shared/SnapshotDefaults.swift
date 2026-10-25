import Foundation

extension DashboardSnapshot {
    static let empty = DashboardSnapshot(
        currentBreakdown: nil,
        activeJobs: [],
        hasSupplementConfiguration: false,
        currentGross: 0,
        currentTakeHome: 0,
        currentEffectiveGross: 0,
        currentEffectiveTakeHome: 0,
        payPeriodAggregation: .unified,
        payPeriodGross: 0,
        payPeriodTakeHome: 0,
        payPeriodEffectiveGross: 0,
        payPeriodEffectiveTakeHome: 0,
        payPeriodHours: 0,
        payPeriodNightPremium: 0,
        allTimeGross: 0,
        allTimeTakeHome: 0,
        allTimeEffectiveGross: 0,
        allTimeEffectiveTakeHome: 0,
        projectedPaycheckGross: 0,
        projectedPaycheckTakeHome: 0,
        projectedPaycheckEffectiveGross: 0,
        projectedPaycheckEffectiveTakeHome: 0,
        projectedConfidenceLabel: "Earned so far",
        allTimeHours: 0
    )
}
