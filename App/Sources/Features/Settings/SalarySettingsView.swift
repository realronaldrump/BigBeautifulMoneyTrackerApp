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
    var paycheckGross: Double { makePlan().paycheckGross }
    var paydayDescription: String {
        if paydayOffsetDays == 0 { return "Payday: when the period ends" }
        let days = abs(paydayOffsetDays)
        return "Payday: \(days) \(days == 1 ? "day" : "days") \(paydayOffsetDays < 0 ? "before" : "after") period ends"
    }
}

/// Shared by first-run setup and the dated salary editor.
struct SalarySetupFields: View {
    @Binding var draft: SalarySetupDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Salary amount", selection: $draft.amountBasis) {
                ForEach(SalaryAmountBasis.allCases) { Text($0.title).tag($0) }
            }
            TextField(
                draft.amountBasis == .annual ? "Annual gross salary" : "Gross per paycheck", text: $draft.amountText
            )
            .keyboardType(.decimalPad)
            .accessibilityLabel(
                draft.amountBasis == .annual ? "Annual gross salary in dollars" : "Gross paycheck in dollars"
            )
            .padding(12).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            Picker("Pay frequency", selection: $draft.frequency) {
                ForEach(PayFrequency.allCases) { Text($0.title).tag($0) }
            }
            if draft.paycheckGross > 0 {
                Text("\(draft.paycheckGross.formatted(.currency(code: "USD"))) gross per paycheck")
                    .font(.callout).foregroundStyle(.secondary)
                if draft.amountBasis == .annual {
                    Text(
                        "Uses \(Int(draft.frequency.periodsPerYear)) paychecks per year. Enter your paycheck amount directly if your employer uses a different calculation."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            DatePicker("Pay cycle anchor", selection: $draft.anchorDate, displayedComponents: .date)
            Text("Choose a known first day of a pay period. This is separate from payday.")
                .font(.caption).foregroundStyle(.secondary)
            DatePicker("Salary starts counting", selection: $draft.effectiveDate, displayedComponents: .date)
            Stepper(draft.paydayDescription, value: $draft.paydayOffsetDays, in: -30...60)
            Picker("Visualize earnings", selection: $draft.accrualMode) {
                ForEach(SalaryAccrualMode.allCases) { Text($0.title).tag($0) }
            }
            Text(
                draft.accrualMode == .continuous
                    ? "The counter grows across every day, including weekends. No start or end times needed."
                    : "The same paycheck is spread across selected weekdays. Paid holidays and vacation keep counting."
            )
            .font(.caption).foregroundStyle(.secondary)
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
                    DatePicker(
                        "Window starts", selection: timeBinding(\.startMinute), displayedComponents: .hourAndMinute)
                    DatePicker("Window ends", selection: timeBinding(\.endMinute), displayedComponents: .hourAndMinute)
                    Text(
                        "Use a daytime window with the end after the start. This only controls the animation; it does not record hours worked."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Schedule time zone: \(draft.timeZoneIdentifier)")
                .font(.caption).foregroundStyle(.secondary)
            Text(
                "Accrual is a visualization estimate. Deposits are recorded separately in salary history. A partial first or last period is prorated."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        .environment(\.timeZone, draft.makePlan().calendar.timeZone)
        .onChange(of: draft.anchorDate) { oldValue, newValue in
            if draft.effectiveDate == oldValue { draft.effectiveDate = newValue }
        }
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
        Form {
            Section {
                SalarySetupFields(draft: $draft)
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
            LabeledContent("Pay type", value: job.compensationKind.title)
            if let plan = jobPlans.first, job.compensationKind == .salary {
                LabeledContent(plan.amountBasis.title, value: plan.amount.formatted(.currency(code: "USD")))
                LabeledContent("Pay frequency", value: plan.frequency.title)
                Text(
                    "From \(plan.effectiveDate.formatted(date: .abbreviated, time: .omitted)) · \(plan.accrualDescription)"
                )
                .font(.caption).foregroundStyle(.secondary)
                NavigationLink("Schedule salary or display change") {
                    SalaryPlanEditorView(job: job, previousPlan: plan)
                }
                if plan.effectiveDate > .now {
                    Button("Cancel upcoming salary change", role: .destructive) { confirmingCancellation = true }
                }
                Button("Switch to hourly pay", role: .destructive) { confirmingHourly = true }
            } else {
                NavigationLink("Set up salary mode") { SalaryPlanEditorView(job: job, previousPlan: jobPlans.first) }
            }
            if !jobPlans.isEmpty {
                NavigationLink("Salary history and paychecks") { SalaryHistoryView(jobIdentifier: job.id) }
            }
            if let errorText { Text(errorText).foregroundStyle(.red) }
        } header: {
            Text("Salary & Pay Type")
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
