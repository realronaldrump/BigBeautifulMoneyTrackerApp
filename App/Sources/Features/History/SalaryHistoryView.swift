import SwiftData
import SwiftUI
import WidgetKit

struct SalaryHistoryView: View {
    var jobIdentifier: UUID? = nil
    @Query(sort: \JobProfile.sortOrder) private var jobs: [JobProfile]
    @Query private var plans: [SalaryPlan]
    @Query private var payments: [SalaryPayment]
    @State private var showsAllPeriods = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            List {
                Section {
                    Text(
                        "Salary accrues automatically. Record a paycheck when you receive it, and optionally log work hours to see your effective hourly rate."
                    )
                    .font(.callout).foregroundStyle(.secondary)
                    Toggle("Include older pay periods", isOn: $showsAllPeriods)
                }
                ForEach(jobs.filter { jobIdentifier == nil || $0.id == jobIdentifier }) { job in
                    let jobPlans = plans.filter { $0.job?.id == job.id }
                    if !jobPlans.isEmpty {
                        Section(job.displayName + (job.isArchived ? " · Archived" : "")) {
                            let cutoff =
                                job.isArchived ? min(timeline.date, job.archivedAt ?? job.updatedAt) : timeline.date
                            let start =
                                showsAllPeriods
                                ? jobPlans.map(\.effectiveDate).min()!
                                : Calendar.current.date(byAdding: .month, value: -12, to: timeline.date)
                                    ?? timeline.date
                            let periods = SalaryEngine.periods(for: jobPlans, from: start, through: cutoff)
                            ForEach(periods, id: \.self) { interval in
                                NavigationLink {
                                    SalaryPeriodDetailView(job: job, interval: interval)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(SalaryEngine.displayRange(interval, calendar: jobPlans.first!.calendar))
                                            .font(.headline)
                                        Text(
                                            SalaryEngine.gross(for: jobPlans, within: interval, through: cutoff),
                                            format: .currency(code: "USD")
                                        )
                                        .font(.title3.bold()).monospacedDigit()
                                        if let payment = payments.first(where: {
                                            $0.job?.id == job.id && $0.periodStart == interval.start
                                                && $0.periodEnd == interval.end
                                        }) {
                                            Label(
                                                "Paid \(payment.paidDate.formatted(date: .abbreviated, time: .omitted))",
                                                systemImage: "checkmark.circle.fill"
                                            )
                                            .font(.caption).foregroundStyle(.green)
                                        } else {
                                            Text("Accrued estimate · no paycheck recorded").font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }.padding(.vertical, 4)
                                }
                            }
                            if periods.isEmpty {
                                Text(
                                    "Salary begins on \(jobPlans.map(\.effectiveDate).min()!.formatted(date: .abbreviated, time: .omitted))."
                                ).foregroundStyle(.secondary)
                            }
                        }
                        Section("Salary agreements · \(job.displayName)") {
                            ForEach(jobPlans.sorted { $0.effectiveDate > $1.effectiveDate }) { plan in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(plan.amount.formatted(.currency(code: "USD"))) · \(plan.amountBasis.title)")
                                        .font(.headline)
                                    Text(
                                        "From \(plan.effectiveDate.formatted(date: .abbreviated, time: .omitted))"
                                            + (plan.endDate.map {
                                                " to \($0.formatted(date: .abbreviated, time: .omitted))"
                                            } ?? ""))
                                    Text("\(plan.frequency.title) · \(plan.accrualDescription)")
                                    Text("\(plan.timeZoneIdentifier)")
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Salary History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SalaryPeriodDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let job: JobProfile
    let interval: DateInterval
    @Query private var plans: [SalaryPlan]
    @Query private var payments: [SalaryPayment]
    @Query(sort: \SalaryWorkLog.date, order: .reverse) private var workLogs: [SalaryWorkLog]
    @State private var editingPayment = false
    @State private var addingHours = false
    @State private var editingHours: SalaryWorkLog?
    @State private var deletingHours: SalaryWorkLog?
    @State private var deletingPayment = false
    @State private var errorText: String?

    private var jobPlans: [SalaryPlan] { plans.filter { $0.job?.id == job.id } }
    private var payment: SalaryPayment? {
        payments.first { $0.job?.id == job.id && $0.periodStart == interval.start && $0.periodEnd == interval.end }
    }
    private var logs: [SalaryWorkLog] {
        workLogs.filter { $0.job?.id == job.id && $0.date >= interval.start && $0.date < interval.end }
    }
    private var expectedGross: Double { SalaryEngine.gross(for: jobPlans, within: interval, through: interval.end) }
    private var calendar: Calendar { jobPlans.first?.calendar ?? .current }

    var body: some View {
        List {
            Section(job.displayName) {
                Text(SalaryEngine.displayRange(interval, calendar: calendar)).font(.headline)
                LabeledContent(
                    "Salary accrued",
                    value: SalaryEngine.gross(
                        for: jobPlans, within: interval,
                        through: job.isArchived ? min(.now, job.archivedAt ?? job.updatedAt) : .now
                    ).formatted(.currency(code: "USD")))
                LabeledContent("Full period estimate", value: expectedGross.formatted(.currency(code: "USD")))
                Text(
                    "Accrued salary is a visualization estimate. Paychecks below are actual amounts you record and do not add to earnings again."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Paycheck received") {
                if let payment {
                    LabeledContent("Paid", value: payment.paidDate.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("Actual gross", value: payment.gross.formatted(.currency(code: "USD")))
                    if let net = payment.takeHome {
                        LabeledContent("Actual take-home", value: net.formatted(.currency(code: "USD")))
                    }
                    if !payment.note.isEmpty { Text(payment.note) }
                    Button("Edit paycheck") { editingPayment = true }
                    Button("Remove paycheck record", role: .destructive) { deletingPayment = true }
                } else {
                    Text("No paycheck recorded").foregroundStyle(.secondary)
                    Button("Record received paycheck") { editingPayment = true }
                }
            }
            Section("Optional work hours") {
                let hours = logs.reduce(0) { $0 + $1.hours }
                LabeledContent("Logged hours", value: hours.formatted(.number.precision(.fractionLength(1))))
                if hours > 0 {
                    let earned = SalaryEngine.gross(for: jobPlans, within: interval, through: .now)
                    LabeledContent(
                        "Effective gross per logged hour",
                        value: (earned / hours).formatted(.currency(code: "USD")) + "/hr")
                }
                ForEach(logs) { log in
                    Button {
                        editingHours = log
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                "\(log.date.formatted(date: .abbreviated, time: .omitted)) · \(log.hours.formatted()) hours"
                            )
                            if !log.note.isEmpty { Text(log.note).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .swipeActions(allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) { deletingHours = log }
                    }
                }
                Button("Log work hours") { addingHours = true }
                Text("Hours never change salary earnings. Effective rate uses only the hours you log.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let errorText { Section { Text(errorText).foregroundStyle(.red) } }
        }
        .navigationTitle("Salary Pay Period")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editingPayment) {
            NavigationStack {
                SalaryPaymentEditorView(job: job, interval: interval, expectedGross: expectedGross, payment: payment)
            }
        }
        .sheet(isPresented: $addingHours) {
            NavigationStack { SalaryHoursEditorView(job: job, interval: interval) }.environment(
                \.timeZone, calendar.timeZone)
        }
        .sheet(item: $editingHours) { log in
            NavigationStack { SalaryHoursEditorView(job: job, interval: interval, log: log) }.environment(
                \.timeZone, calendar.timeZone)
        }
        .confirmationDialog("Remove paycheck record?", isPresented: $deletingPayment, titleVisibility: .visible) {
            Button("Remove record", role: .destructive) { if let payment { remove(payment) } }
        } message: {
            Text("This removes the recorded deposit. Accrued salary stays the same.")
        }
        .confirmationDialog(
            "Delete work hours?",
            isPresented: Binding(get: { deletingHours != nil }, set: { if !$0 { deletingHours = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete hours", role: .destructive) {
                if let log = deletingHours {
                    remove(log)
                    deletingHours = nil
                }
            }
        }
    }

    private func remove<T: PersistentModel>(_ record: T) {
        do {
            modelContext.delete(record)
            try PersistenceService.save(modelContext)
            WidgetCenter.shared.reloadAllTimelines()
        } catch { errorText = error.localizedDescription }
    }
}

private struct SalaryPaymentEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let job: JobProfile
    let interval: DateInterval
    let payment: SalaryPayment?
    @State private var grossText: String
    @State private var takeHomeText: String
    @State private var paidDate: Date
    @State private var note: String
    @State private var errorText: String?

    init(job: JobProfile, interval: DateInterval, expectedGross: Double, payment: SalaryPayment?) {
        self.job = job
        self.interval = interval
        self.payment = payment
        _grossText = State(initialValue: LocalizedNumericInput.decimalText(for: payment?.gross ?? expectedGross))
        _takeHomeText = State(initialValue: payment?.takeHome.map { LocalizedNumericInput.decimalText(for: $0) } ?? "")
        _paidDate = State(initialValue: payment?.paidDate ?? .now)
        _note = State(initialValue: payment?.note ?? "")
    }
    var body: some View {
        Form {
            Section("Actual paycheck") {
                Text(interval.displayRange)
                TextField("Gross amount", text: $grossText).keyboardType(.decimalPad)
                TextField("Take-home amount (optional)", text: $takeHomeText).keyboardType(.decimalPad)
                DatePicker("Received on", selection: $paidDate, in: ...Date.now, displayedComponents: .date)
                TextField("Notes", text: $note, axis: .vertical)
            }
            if let errorText { Text(errorText).foregroundStyle(.red) }
        }
        .navigationTitle(payment == nil ? "Record Paycheck" : "Edit Paycheck")
        .appKeyboardToolbar()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    do {
                        guard let gross = LocalizedNumericInput.decimalValue(from: grossText) else {
                            throw SalaryServiceError.invalidAmount
                        }
                        let net =
                            takeHomeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? nil : LocalizedNumericInput.decimalValue(from: takeHomeText)
                        if !takeHomeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && net == nil {
                            throw SalaryServiceError.invalidAmount
                        }
                        try SalaryService.savePayment(
                            job: job, interval: interval, paidDate: paidDate, gross: gross, takeHome: net, note: note,
                            editing: payment, in: modelContext)
                        WidgetCenter.shared.reloadAllTimelines()
                        dismiss()
                    } catch { errorText = error.localizedDescription }
                }
            }
        }
    }
}

private struct SalaryHoursEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let job: JobProfile
    let interval: DateInterval
    let log: SalaryWorkLog?
    @State private var date: Date
    @State private var hoursText: String
    @State private var note: String
    @State private var errorText: String?
    init(job: JobProfile, interval: DateInterval, log: SalaryWorkLog? = nil) {
        self.job = job
        self.interval = interval
        self.log = log
        _date = State(initialValue: log?.date ?? min(.now, interval.end.addingTimeInterval(-1)))
        _hoursText = State(initialValue: log.map { LocalizedNumericInput.decimalText(for: $0.hours) } ?? "")
        _note = State(initialValue: log?.note ?? "")
    }
    var body: some View {
        Form {
            Section {
                DatePicker(
                    "Work date", selection: $date,
                    in: interval.start...max(interval.start, min(.now, interval.end.addingTimeInterval(-1))),
                    displayedComponents: .date)
                TextField("Hours worked", text: $hoursText).keyboardType(.decimalPad)
                TextField("Notes", text: $note, axis: .vertical)
                Text("Optional hours help you understand your effective rate. Your fixed salary stays the same.").font(
                    .caption
                ).foregroundStyle(.secondary)
            }
            if let errorText { Text(errorText).foregroundStyle(.red) }
        }
        .navigationTitle("Work Hours")
        .appKeyboardToolbar()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    do {
                        guard let hours = LocalizedNumericInput.decimalValue(from: hoursText) else {
                            throw SalaryServiceError.invalidHours
                        }
                        try SalaryService.saveWorkLog(
                            job: job, date: date, hours: hours, note: note, editing: log, in: modelContext)
                        WidgetCenter.shared.reloadAllTimelines()
                        dismiss()
                    } catch { errorText = error.localizedDescription }
                }
            }
        }
    }
}
