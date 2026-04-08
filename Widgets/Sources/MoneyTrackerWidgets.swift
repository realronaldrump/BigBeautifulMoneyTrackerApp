import ActivityKit
import SwiftData
import SwiftUI
import WidgetKit

struct MoneyTrackerWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: DashboardSnapshot
    let mode: EarningsDisplayMode
    let isShiftActive: Bool
}

struct MoneyTrackerWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MoneyTrackerWidgetEntry {
        MoneyTrackerWidgetEntry(date: .now, snapshot: .preview, mode: .gross, isShiftActive: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (MoneyTrackerWidgetEntry) -> Void) {
        completion(loadEntry(for: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MoneyTrackerWidgetEntry>) -> Void) {
        let initialEntry = loadEntry(for: .now)
        let entries: [MoneyTrackerWidgetEntry]

        if initialEntry.isShiftActive {
            entries = (0..<4).map { index in
                let date = Calendar.current.date(byAdding: .minute, value: index * 15, to: .now) ?? .now
                return loadEntry(for: date)
            }
        } else {
            entries = [initialEntry]
        }

        completion(Timeline(entries: entries, policy: .after(Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now)))
    }

    private func loadEntry(for date: Date) -> MoneyTrackerWidgetEntry {
        let container = AppModelContainerFactory.makeSharedContainer()
        let context = ModelContext(container)
        let completedShifts = (try? context.fetch(FetchDescriptor<ShiftRecord>())) ?? []
        let payRates = (try? context.fetch(FetchDescriptor<PayRateSchedule>())) ?? []
        let templates = (try? context.fetch(FetchDescriptor<ScheduleTemplate>())) ?? []
        let preferences = (try? context.fetch(FetchDescriptor<AppPreferences>()))?.first
        let openShift = (try? context.fetch(FetchDescriptor<OpenShiftState>()))?.first
        let nightRule = (try? context.fetch(FetchDescriptor<NightDifferentialRule>()))?.first ?? NightDifferentialRule()
        let overtimeRule = (try? context.fetch(FetchDescriptor<OvertimeRuleSet>()))?.first
        let taxProfile = (try? context.fetch(FetchDescriptor<TaxProfile>()))?.first ?? TaxProfile()
        let paySchedule = (try? context.fetch(FetchDescriptor<PaySchedule>()))?.first ?? PaySchedule()

        let currentBreakdown: EarningsBreakdown?
        if let openShift {
            currentBreakdown = EarningsEngine.calculate(
                start: openShift.startDate,
                end: date,
                payRates: payRates,
                nightRule: nightRule,
                overtimeRule: overtimeRule,
                historicalShifts: completedShifts
            )
        } else {
            currentBreakdown = nil
        }

        let ytdGross = AggregationService.totalGross(for: completedShifts, in: Calendar.current.dateInterval(of: .year, for: date))
        let currentRate = currentBreakdown?.effectiveRate ?? EarningsEngine.payRate(at: date, payRates: payRates)
        let estimate = TaxEstimator.estimate(
            currentGross: currentBreakdown?.grossEarnings ?? 0,
            yearToDateGrossExcludingCurrentShift: ytdGross,
            payFrequency: paySchedule.frequency,
            taxProfile: taxProfile,
            currentHourlyRate: currentRate,
            templates: templates,
            today: date
        )
        let takeHomeRate = estimate.estimatedWithholdingRate
        let projection = ProjectionEngine.projectedPaycheck(
            asOf: date,
            shifts: completedShifts,
            openShiftBreakdown: currentBreakdown,
            paySchedule: paySchedule,
            payRates: payRates,
            templates: templates,
            takeHomeRate: takeHomeRate
        )
        let payPeriodInterval = ProjectionEngine.payPeriodInterval(for: date, schedule: paySchedule)
        let allTimeGross = AggregationService.totalGross(for: completedShifts) + (currentBreakdown?.grossEarnings ?? 0)

        let snapshot = DashboardSnapshot(
            currentBreakdown: currentBreakdown,
            currentGross: currentBreakdown?.grossEarnings ?? 0,
            currentTakeHome: estimate.currentShiftNetEstimate,
            payPeriodGross: projection.payPeriodGross,
            payPeriodTakeHome: projection.payPeriodGross * (1 - takeHomeRate),
            payPeriodHours: projection.payPeriodHours,
            payPeriodNightPremium: AggregationService.totalNightPremium(for: completedShifts, in: payPeriodInterval) + (currentBreakdown?.nightPremiumEarnings ?? 0),
            allTimeGross: allTimeGross,
            allTimeTakeHome: allTimeGross * (1 - takeHomeRate),
            projectedPaycheckGross: projection.projectedGross,
            projectedPaycheckTakeHome: projection.projectedTakeHome,
            projectedConfidenceLabel: projection.confidenceLabel,
            weeklyGross: AggregationService.totalGross(for: completedShifts, in: Calendar.current.dateInterval(of: .weekOfYear, for: date)) + (currentBreakdown?.grossEarnings ?? 0),
            allTimeHours: AggregationService.totalHours(for: completedShifts) + (currentBreakdown?.totalHours ?? 0)
        )

        return MoneyTrackerWidgetEntry(
            date: date,
            snapshot: snapshot,
            mode: preferences?.selectedDisplayMode ?? .gross,
            isShiftActive: snapshot.currentBreakdown != nil
        )
    }
}

struct MoneyTrackerWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: MoneyTrackerWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .accessoryRectangular:
            accessoryView
        default:
            mediumView
        }
    }

    private var amount: Double {
        entry.mode == .gross ? entry.snapshot.currentGross : entry.snapshot.currentTakeHome
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entry.mode == .gross ? "Gross" : "Take Home")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(amount, format: .currency(code: "USD"))
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(2)
            Spacer()
            Text(entry.isShiftActive ? "Shift active" : "Ready to start")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.black, for: .widget)
    }

    private var mediumView: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.mode == .gross ? "Current Shift" : "Estimated Net")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(amount, format: .currency(code: "USD"))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(entry.isShiftActive ? "Live in app, synced here." : "Start a shift in the app.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 12) {
                stat("Pay Period", entry.mode == .gross ? entry.snapshot.payPeriodGross : entry.snapshot.payPeriodTakeHome)
                stat("Projected", entry.mode == .gross ? entry.snapshot.projectedPaycheckGross : entry.snapshot.projectedPaycheckTakeHome)
                stat("All Time", entry.mode == .gross ? entry.snapshot.allTimeGross : entry.snapshot.allTimeTakeHome)
            }
        }
        .containerBackground(.black, for: .widget)
    }

    private var accessoryView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.mode == .gross ? "Money" : "Net")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(amount, format: .currency(code: "USD"))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(1)
            if entry.isShiftActive {
                Text("Shift active")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stat(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value, format: .currency(code: "USD"))
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
    }
}

struct MoneyShiftActivityView: View {
    let context: ActivityViewContext<ShiftActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(context.state.mode == .gross ? "Current Gross" : "Estimated Net")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(context.state.syncedAmount, format: .currency(code: "USD"))
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            HStack {
                Text(context.state.startDate, style: .timer)
                Spacer()
                Text("\(context.state.currentRate, format: .currency(code: "USD"))/hr")
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
        }
        .padding()
        .activityBackgroundTint(.black)
        .activitySystemActionForegroundColor(.white)
    }
}

@main
struct BigBeautifulMoneyTrackerWidgets: WidgetBundle {
    var body: some Widget {
        MoneyTrackerWidget()
        MoneyShiftActivity()
    }
}

struct MoneyTrackerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MoneyTrackerWidget", provider: MoneyTrackerWidgetProvider()) { entry in
            MoneyTrackerWidgetView(entry: entry)
        }
        .configurationDisplayName("Money Tracker")
        .description("See your current shift, pay period, and projected paycheck.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct MoneyShiftActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShiftActivityAttributes.self) { context in
            MoneyShiftActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("Shift")
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.syncedAmount, format: .currency(code: "USD"))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startDate, style: .timer)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
            } compactLeading: {
                Text("$$")
            } compactTrailing: {
                Text(context.state.syncedAmount, format: .currency(code: "USD"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            } minimal: {
                Text("$")
            }
        }
    }
}

private extension DashboardSnapshot {
    static let preview = DashboardSnapshot(
        currentBreakdown: nil,
        currentGross: 138.24,
        currentTakeHome: 104.63,
        payPeriodGross: 1_482.40,
        payPeriodTakeHome: 1_119.12,
        payPeriodHours: 36,
        payPeriodNightPremium: 64.80,
        allTimeGross: 42_820.34,
        allTimeTakeHome: 31_870.92,
        projectedPaycheckGross: 2_964.80,
        projectedPaycheckTakeHome: 2_238.24,
        projectedConfidenceLabel: "Template projected",
        weeklyGross: 741.20,
        allTimeHours: 1_061.5
    )
}
