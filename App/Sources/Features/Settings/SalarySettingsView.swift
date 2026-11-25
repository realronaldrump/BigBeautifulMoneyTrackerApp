import SwiftData
import SwiftUI
import WidgetKit

struct SalarySetupDraft {
    var amountText = ""
    var amountBasis: SalaryAmountBasis = .annual
    var frequency: PayFrequency = .biweekly
    var anchorDate = Calendar.current.startOfDay(for: .now)
    var effectiveDate = Calendar.current.startOfDay(for: .now)
    var paydayOffsetDays = 0
    var accrualMode: SalaryAccrualMode = .continuous
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    var usesWorkHours = false
    var startMinute = 9 * 60
    var endMinute = 17 * 60
    var timeZoneIdentifier = TimeZone.current.identifier

    init(plan: SalaryPlan? = nil, now: Date = .now) {
        guard let plan else { return }
        amountText = LocalizedNumericInput.decimalText(for: plan.amount)
        amountBasis = plan.amountBasis
        frequency = plan.frequency
        anchorDate = plan.anchorDate
        paydayOffsetDays = plan.paydayOffsetDays
        accrualMode = plan.accrualMode
        weekdays = plan.weekdays
        usesWorkHours = plan.usesWorkHours
        startMinute = plan.startMinute
        endMinute = plan.endMinute
        timeZoneIdentifier = plan.timeZoneIdentifier
        effectiveDate = SalaryEngine.period(for: plan, at: max(now, plan.effectiveDate)).end
    }

    func makePlan() -> SalaryPlan {
        SalaryPlan(
            effectiveDate: effectiveDate,
            amount: LocalizedNumericInput.decimalValue(from: amountText) ?? 0,
            amountBasis: amountBasis, frequency: frequency, anchorDate: anchorDate,
            paydayOffsetDays: paydayOffsetDays, accrualMode: accrualMode,
            weekdays: weekdays, usesWorkHours: usesWorkHours, startMinute: startMinute, endMinute: endMinute,
            timeZoneIdentifier: timeZoneIdentifier)
    }
    var isValid: Bool { (try? SalaryService.validate(makePlan())) != nil }

}

/// Shared by first-run setup and the dated salary editor.
struct SalarySetupFields: View {
    @Binding var draft: SalarySetupDraft
    var showsStartDate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TimecardPicker("Salary amount", selection: $draft.amountBasis, options: SalaryAmountBasis.allCases, name: \.title)
            TextField(
                draft.amountBasis == .annual ? "Annual gross salary" : "Gross per paycheck", text: $draft.amountText
            )
            .keyboardType(.decimalPad)
            .accessibilityLabel(
                draft.amountBasis == .annual ? "Annual gross salary in dollars" : "Gross paycheck in dollars"
            )
            .padding(12).background(TimecardColor.inset, in: RoundedRectangle(cornerRadius: 4))
            TimecardPicker("Pay frequency", selection: $draft.frequency, options: PayFrequency.allCases, name: \.title)
            TimecardDateField("A pay period began", selection: $draft.anchorDate, components: .date)
            if showsStartDate {
                TimecardDateField("Track from", selection: $draft.effectiveDate, components: .date)
            }
            DisclosureGroup("Tracking options") {
                VStack(alignment: .leading, spacing: 12) {
                    if !showsStartDate {
                        TimecardDateField("Track from", selection: $draft.effectiveDate, components: .date)
                    }
                    paydayPicker
                    TimecardPicker("Count earnings", selection: $draft.accrualMode, options: SalaryAccrualMode.allCases, name: \.title)
                    if draft.accrualMode == .workdays {
                        ForEach(ScheduleWeekday.allCases) { weekday in
                            Toggle(
                                weekday.title,
                                isOn: Binding(
                                    get: { draft.weekdays.contains(weekday.rawValue) },
                                    set: { selected in
                                        if selected {
                                            draft.weekdays.insert(weekday.rawValue)
                                        } else {
                                            draft.weekdays.remove(weekday.rawValue)
                                        }
                                    }))
                        }
                        Toggle("Use a standard work window", isOn: $draft.usesWorkHours)
                        if draft.usesWorkHours {
                            TimecardDateField(
                                "Window starts", selection: timeBinding(\.startMinute), components: .time)
                            TimecardDateField("Window ends", selection: timeBinding(\.endMinute), components: .time)
                        }
                    }
                }
            }
        }
        .environment(\.timeZone, draft.makePlan().calendar.timeZone)
        .onChange(of: draft.anchorDate) { oldValue, newValue in
            if draft.effectiveDate == oldValue { draft.effectiveDate = newValue }
        }
    }

    private var paydayPicker: some View {
        let plan = draft.makePlan()
        let calendar = plan.calendar
        let end = SalaryEngine.period(for: plan, at: draft.anchorDate).end
        let earliest = calendar.date(byAdding: .day, value: -30, to: end) ?? end
        let latest = calendar.date(byAdding: .day, value: 60, to: end) ?? end
        return TimecardDateField("Payday for that period", selection: Binding(
            get: { calendar.date(byAdding: .day, value: draft.paydayOffsetDays, to: end) ?? end },
            set: { draft.paydayOffsetDays = calendar.dateComponents([.day], from: end, to: $0).day ?? 0 }
        ), minimum: earliest, maximum: latest, components: .date)
    }

    private func timeBinding(_ keyPath: WritableKeyPath<SalarySetupDraft, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = draft[keyPath: keyPath]
                return draft.makePlan().calendar.date(
                    bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = draft.makePlan().calendar.dateComponents([.hour, .minute], from: date)
                draft[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            })
    }
}

struct SalaryPlanEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let job: JobProfile
    let previousPlan: SalaryPlan?
    @State private var draft: SalarySetupDraft
    @State private var errorText: String?

    init(job: JobProfile, previousPlan: SalaryPlan? = nil) {
        self.job = job
        self.previousPlan = previousPlan
        _draft = State(initialValue: SalarySetupDraft(plan: previousPlan))
    }

    var body: some View {
        TimecardForm {
            Section {
                SalarySetupFields(draft: $draft, showsStartDate: true)
            } header: {
                Text(previousPlan == nil ? "Set up salary" : "New salary agreement")
            } footer: {
                Text(
                    previousPlan == nil
                        ? "Hourly history stays saved. Salary must start after your last hourly shift. Upcoming hourly schedules and templates for this job will be removed."
                        : "Changes start at a pay-period boundary. The suggested date is the next period. Earlier agreements stay saved so history does not change."
                )
            }
            if let errorText { Section { Text(errorText).foregroundStyle(.red) } }
            Section {
                Button(previousPlan == nil ? "Start automatic salary tracking" : "Save salary change") {
                    do {
                        try SalaryService.savePlan(draft.makePlan(), for: job, in: modelContext)
                        WidgetCenter.shared.reloadAllTimelines()
                        dismiss()
                    } catch { errorText = error.localizedDescription }
                }
                .disabled(!draft.isValid)
            }
        }
        .navigationTitle(job.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .appKeyboardToolbar()
    }
}

struct SalaryPaydayEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let jobID: UUID
    @State private var payday: ScheduledSalaryPayday
    @State private var selection: Date
    @State private var errorText: String?

    init(jobID: UUID, payday: ScheduledSalaryPayday) {
        self.jobID = jobID
        _payday = State(initialValue: payday)
        _selection = State(initialValue: payday.date)
    }

    private var selectableDates: ClosedRange<Date> {
        let calendar = payday.calendar
        let today = calendar.startOfDay(for: .now)
        let earliest = max(today, calendar.date(byAdding: .day, value: -30, to: payday.period.end) ?? today)
        let latest = calendar.date(byAdding: .day, value: 60, to: payday.period.end) ?? earliest
        return earliest...max(earliest, latest)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TimecardCalendar(selection: $selection, minimum: selectableDates.lowerBound, maximum: selectableDates.upperBound)
                Text("Choose the date printed on your paycheck. It repeats with your pay cycle, even if your bank posts the deposit early.")
                    .font(TypeStyle.caption).foregroundStyle(TimecardColor.graphite)
                if let errorText { AppInlineNotice(message: errorText) }
            }.padding(20)
        }
        .background(TimecardColor.stock.ignoresSafeArea())
        .environment(\.timeZone, payday.calendar.timeZone)
        .environment(\.calendar, payday.calendar)
        .navigationTitle("Official payday")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    do {
                        try SalaryService.correctPayday(payday, for: jobID, to: selection, in: modelContext)
                        WidgetCenter.shared.reloadAllTimelines()
                        dismiss()
                    } catch { errorText = error.localizedDescription }
                }.disabled(payday.calendar.isDate(selection, inSameDayAs: payday.date))
            }
        }
    }
}

struct SalarySettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    let job: JobProfile
    @Query(sort: \SalaryPlan.effectiveDate, order: .reverse) private var plans: [SalaryPlan]
    @State private var confirmingHourly = false
    @State private var confirmingCancellation = false
    @State private var errorText: String?
    private var jobPlans: [SalaryPlan] { plans.filter { $0.job?.id == job.id } }

    var body: some View {
        Section {
            if let plan = jobPlans.first, job.compensationKind == .salary {
                LabeledContent(plan.amountBasis.title, value: plan.amount.formatted(.currency(code: "USD")))
                LabeledContent("Pay frequency", value: plan.frequency.title)
                let now = Date.now
                if let active = SalaryEngine.currentOrUpcomingPlan(in: jobPlans, at: now) {
                    let payday = SalaryEngine.scheduledPayday(for: jobPlans, at: now, plan: active)
                    NavigationLink {
                        SalaryPaydayEditor(jobID: job.id, payday: payday)
                    } label: { LabeledContent("Official payday", value: payday.label) }
                }
                Text(
                    "From \(plan.effectiveDate.formatted(date: .abbreviated, time: .omitted)) · \(plan.accrualDescription)"
                )
                .font(.caption).foregroundStyle(.secondary)
                NavigationLink("Change salary") {
                    SalaryPlanEditorView(job: job, previousPlan: plan)
                }
                if plan.effectiveDate > .now {
                    Button("Cancel upcoming salary change", role: .destructive) { confirmingCancellation = true }
                }
                Button("Switch to hourly pay", role: .destructive) { confirmingHourly = true }
            } else {
                NavigationLink("Switch to salary") { SalaryPlanEditorView(job: job, previousPlan: jobPlans.first) }
            }
            if !jobPlans.isEmpty {
                NavigationLink("Salary history and paychecks") { SalaryHistoryView(jobIdentifier: job.id) }
            }
            if let errorText { Text(errorText).foregroundStyle(.red) }
        } header: {
            Text("Salary")
        }
        .confirmationDialog("Switch to hourly pay?", isPresented: $confirmingHourly, titleVisibility: .visible) {
            Button("Stop salary and switch to hourly", role: .destructive) {
                do {
                    try SalaryService.switchToHourly(job: job, in: modelContext)
                    WidgetCenter.shared.reloadAllTimelines()
                } catch { errorText = error.localizedDescription }
            }
        } message: {
            Text(
                "Salary will stop counting now. Earlier salary earnings, work hours, and paycheck records stay saved. Add an hourly rate to start tracking shifts."
            )
        }
        .confirmationDialog(
            "Cancel upcoming salary change?", isPresented: $confirmingCancellation, titleVisibility: .visible
        ) {
            Button("Cancel upcoming change", role: .destructive) {
                guard let plan = jobPlans.first else { return }
                do {
                    try SalaryService.cancelUpcomingPlan(plan, in: modelContext)
                    WidgetCenter.shared.reloadAllTimelines()
                } catch { errorText = error.localizedDescription }
            }
        } message: {
            Text(
                "The current salary agreement will continue. A first salary agreement that has not started yet returns this job to hourly pay."
            )
        }
    }
}
