import ActivityKit
import SwiftData
import SwiftUI
import WidgetKit

struct MoneyTrackerWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: DashboardSnapshot
    let mode: EarningsDisplayMode
    let isShiftActive: Bool
    let activeJobCount: Int
}

struct MoneyTrackerWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MoneyTrackerWidgetEntry {
        MoneyTrackerWidgetEntry(date: .now, snapshot: .preview, mode: .gross, isShiftActive: false, activeJobCount: 0)
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
        try? DataBootstrapper.seedIfNeeded(in: context)
        let preferences = (try? context.fetch(FetchDescriptor<AppPreferences>()))?.first
        let openShifts = (try? context.fetch(FetchDescriptor<OpenShiftState>())) ?? []
        let snapshot = (try? ShiftController.dashboardSnapshot(in: context, at: date)) ?? .preview

        return MoneyTrackerWidgetEntry(
            date: date,
            snapshot: snapshot,
            mode: preferences?.selectedDisplayMode ?? .gross,
            isShiftActive: !openShifts.isEmpty,
            activeJobCount: openShifts.count
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

    private var widgetBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color.black,
                Color(red: 0.08, green: 0.10, blue: 0.12),
                Color(red: 0.16, green: 0.23, blue: 0.19)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Davis's Big Beautiful")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
                .lineLimit(2)

            Text(entry.mode == .gross ? "Gross" : "Take Home")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(amount, format: .currency(code: "USD"))
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(2)
            Spacer()
            Text(statusText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(widgetBackground, for: .widget)
    }

    private var mediumView: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Davis's Big Beautiful Money Tracker App")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)

                Text(entry.mode == .gross ? "Current Shift" : "Estimated Net")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(amount, format: .currency(code: "USD"))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(statusText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 12) {
                stat("Pay Period", payPeriodText)
                stat("Projected", projectedText)
                stat("All Time", formattedAmount(entry.mode == .gross ? entry.snapshot.allTimeGross : entry.snapshot.allTimeTakeHome))
            }
        }
        .containerBackground(widgetBackground, for: .widget)
    }

    private var accessoryView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Davis's")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(amount, format: .currency(code: "USD"))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(1)
            if entry.isShiftActive {
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        guard entry.isShiftActive else {
            return "Ready to start"
        }

        if entry.activeJobCount == 1 {
            return "1 job active"
        }

        return "\(entry.activeJobCount) jobs active"
    }

    private var payPeriodText: String {
        guard entry.snapshot.payPeriodAggregation == .unified else {
            return "Varies"
        }

        return formattedAmount(entry.mode == .gross ? entry.snapshot.payPeriodGross : entry.snapshot.payPeriodTakeHome)
    }

    private var projectedText: String {
        guard entry.snapshot.payPeriodAggregation == .unified else {
            return "Varies"
        }

        return formattedAmount(entry.mode == .gross ? entry.snapshot.projectedPaycheckGross : entry.snapshot.projectedPaycheckTakeHome)
    }

    private func formattedAmount(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
    }
}

struct MoneyShiftActivityView: View {
    let context: ActivityViewContext<ShiftActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)

                Text(context.state.mode == .gross ? "Current Gross" : "Estimated Net")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

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
        .activityBackgroundTint(Color(red: 0.08, green: 0.10, blue: 0.12))
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
        .configurationDisplayName("Davis's Big Beautiful Money Tracker App")
        .description("See live shift totals and projected pay from Davis's Big Beautiful Money Tracker App.")
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
        activeJobs: [],
        currentGross: 138.24,
        currentTakeHome: 104.63,
        payPeriodAggregation: .unified,
        payPeriodGross: 1_482.40,
        payPeriodTakeHome: 1_119.12,
        payPeriodHours: 36,
        payPeriodNightPremium: 64.80,
        allTimeGross: 42_820.34,
        allTimeTakeHome: 31_870.92,
        projectedPaycheckGross: 2_964.80,
        projectedPaycheckTakeHome: 2_238.24,
        projectedConfidenceLabel: "Template projected",
        allTimeHours: 1_061.5
    )
}
