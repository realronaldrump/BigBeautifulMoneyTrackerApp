import SwiftData
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppTheme.self) private var theme
    @Query private var preferences: [AppPreferences]
    @Query(sort: \JobProfile.sortOrder) private var jobs: [JobProfile]
    @Query private var rates: [PayRateSchedule]
    @Query private var schedules: [PaySchedule]
    @State private var creatingJob = false
    @State private var pendingJob: JobProfile?
    @State private var createdJob: JobProfile?

    private var activeJobs: [JobProfile] { jobs.filter { !$0.isArchived } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TimecardHeading(title: "Your pay")
                ForEach(activeJobs) { job in
                    NavigationLink {
                        JobSettingsView(job: job)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                JobInitialBadge(name: job.displayName, accent: job.accent.color, size: 34)
                                Text(job.displayName).font(TypeStyle.title).foregroundStyle(TimecardColor.ink)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right").font(.subheadline).foregroundStyle(TimecardColor.graphite)
                            }
                            Text(payDescription(for: job)).font(.body.monospacedDigit())
                            if let reference = job.paycheckReference {
                                Text(reference.netRate.formatted(.percent.precision(.fractionLength(0...2))) + " take-home on reference check")
                                    .font(.footnote).foregroundStyle(TimecardColor.graphite)
                            }
                        }
                        .foregroundStyle(TimecardColor.ink)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).ruledSection()
                    .accessibilityLabel(job.displayName).accessibilityValue(payDescription(for: job))
                }
                if activeJobs.count < JobService.maxJobs {
                    Button("Add job", systemImage: "plus") { creatingJob = true }
                        .font(.headline).frame(minHeight: 52).padding(.bottom, 8)
                }
                if let preferences = preferences.first {
                    NavigationLink {
                        AppPreferencesView(preferences: preferences)
                    } label: {
                        HStack {
                            Text("App preferences").font(TypeStyle.title2)
                            Spacer()
                            Image(systemName: "chevron.right").font(.subheadline)
                        }
                        .foregroundStyle(TimecardColor.ink).frame(minHeight: 54)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).ruledSection()
                }
            }
            .padding(20)
        }
        .background(MoneyBackground())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .tint(theme.grossAccent)
        .sheet(isPresented: $creatingJob, onDismiss: { createdJob = pendingJob; pendingJob = nil }) {
            NavigationStack { JobEditorView { pendingJob = $0 } }
        }
        .navigationDestination(item: $createdJob) { JobSettingsView(job: $0) }
    }

    private func payDescription(for job: JobProfile) -> String {
        if job.compensationKind == .salary { return "Salary" }
        let jobRates = rates.filter { $0.job?.id == job.id }
        guard !jobRates.isEmpty else { return "Set up hourly pay" }
        let rate = EarningsEngine.payRate(at: .now, payRates: jobRates).formatted(.currency(code: "USD"))
        let cycle = schedules.first { $0.job?.id == job.id }?.frequency.title
        return [rate + "/hr", cycle].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct AppPreferencesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var preferences: AppPreferences
    @State private var notificationsDenied = false

    var body: some View {
        TimecardForm {
            Section("On this iPhone") {
                Toggle("Haptics", isOn: $preferences.hapticsEnabled)
                Toggle("Live Activities", isOn: $preferences.liveActivitiesEnabled)
                Toggle("Show earnings in widgets", isOn: $preferences.lockScreenWidgetsEnabled)
                Toggle("Weekly shift reminders", isOn: $preferences.remindersEnabled)
                if preferences.remindersEnabled && notificationsDenied,
                   let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Allow notifications in iPhone Settings", destination: url)
                }
            }
            Section("About") {
                BrandSignature()
                Text("Pay and shift records are stored on this iPhone and shared with its widgets. Your device backup settings apply.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("App preferences")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scenePhase) {
            notificationsDenied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
        }
        .onChange(of: preferences.remindersEnabled) { _, enabled in
            if enabled { Task { notificationsDenied = !(await ReminderManager.shared.requestAuthorization()) } }
        }
        .onDisappear { PersistenceService.saveReportingFailure(modelContext) }
    }
}

private struct JobSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var job: JobProfile

    @Query(sort: \PayRateSchedule.effectiveDate, order: .reverse) private var payRates: [PayRateSchedule]
    @Query private var nightRules: [NightDifferentialRule]
    @Query private var overtimeRules: [OvertimeRuleSet]
    @Query private var paySchedules: [PaySchedule]
    @Query private var supplements: [JobSupplement]

    @State private var editingRate: PayRateSchedule?
    @State private var creatingRate = false
    @State private var editingSupplement: JobSupplement?
    @State private var creatingSupplement = false

    private var jobPayRates: [PayRateSchedule] {
        payRates.filter { $0.job?.id == job.id }
    }

    private var jobSupplements: [JobSupplement] {
        supplements
            .filter { $0.job?.id == job.id }
            .sorted {
                if $0.startDate == $1.startDate {
                    return $0.createdAt > $1.createdAt
                }
                return $0.startDate > $1.startDate
            }
    }

    private var nightRule: NightDifferentialRule? {
        nightRules.first { $0.job?.id == job.id }
    }

    private var overtimeRule: OvertimeRuleSet? {
        overtimeRules.first { $0.job?.id == job.id }
    }

    private var paySchedule: PaySchedule? {
        paySchedules.first { $0.job?.id == job.id }
    }

    var body: some View {
        Group {
            if let nightRule,
               let overtimeRule,
               let paySchedule {
                JobSettingsForm(
                    job: job,
                    payRates: jobPayRates,
                    supplements: jobSupplements,
                    paySchedule: paySchedule,
                    nightRule: nightRule,
                    overtimeRule: overtimeRule,
                    editingRate: $editingRate,
                    creatingRate: $creatingRate,
                    editingSupplement: $editingSupplement,
                    creatingSupplement: $creatingSupplement
                )
                .scrollContentBackground(.hidden)
                .background(MoneyBackground())
                .navigationTitle(job.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .sheet(item: $editingRate) { rate in
                    NavigationStack {
                        RateEditorView(job: job, editingRate: rate)
                    }
                }
                .sheet(isPresented: $creatingRate) {
                    NavigationStack {
                        RateEditorView(job: job, editingRate: nil)
                    }
                }
                .sheet(item: $editingSupplement) { supplement in
                    NavigationStack {
                        SupplementEditorView(job: job, editingSupplement: supplement)
                    }
                }
                .sheet(isPresented: $creatingSupplement) {
                    NavigationStack {
                        SupplementEditorView(job: job, editingSupplement: nil)
                    }
                }
                .onDisappear {
                    PersistenceService.saveReportingFailure(modelContext)
                }
            } else {
                ProgressView()
                    .tint(TimecardColor.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(TimecardColor.stock.ignoresSafeArea())
                    .task {
                        try? DataBootstrapper.seedIfNeeded(in: modelContext)
                    }
            }
        }
        .tint(job.accent.color)
    }
}

private struct JobSettingsForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var job: JobProfile
    let payRates: [PayRateSchedule]
    let supplements: [JobSupplement]
    @Bindable var paySchedule: PaySchedule
    @Bindable var nightRule: NightDifferentialRule
    @Bindable var overtimeRule: OvertimeRuleSet

    @Query private var preferences: [AppPreferences]
    @Query(sort: \JobProfile.sortOrder) private var jobs: [JobProfile]
    @Query private var templates: [ScheduleTemplate]

    @Binding var editingRate: PayRateSchedule?
    @Binding var creatingRate: Bool
    @Binding var editingSupplement: JobSupplement?
    @Binding var creatingSupplement: Bool

    @State private var confirmingDeletion = false
    @State private var deleteErrorText: String?

    var body: some View {
        TimecardForm {
            Section("Pay") {
                NavigationLink {
                    PaycheckSettingsView(job: job)
                } label: {
                    LabeledContent("Take-home pay", value: job.paycheckReference.map {
                        $0.netRate.formatted(.percent.precision(.fractionLength(2)))
                    } ?? "Add paycheck")
                }
                if job.compensationKind == .hourly {
                    if payRates.isEmpty {
                        Button("Add hourly rate") { creatingRate = true }
                    } else {
                        DisclosureGroup {
                            ForEach(payRates) { rate in
                                Button { editingRate = rate } label: {
                                    LabeledContent(rate.effectiveDate.formatted(date: .abbreviated, time: .omitted),
                                                   value: rate.hourlyRate.formatted(.currency(code: "USD")))
                                }
                            }
                            Button("Add a rate change") { creatingRate = true }
                        } label: {
                            LabeledContent("Hourly rate", value: EarningsEngine.payRate(at: .now, payRates: payRates).formatted(.currency(code: "USD")))
                        }
                    }
                    NavigationLink {
                        TimecardForm {
                            Picker("Paid", selection: $paySchedule.frequencyRawValue) {
                                ForEach(PayFrequency.allCases) { Text($0.title).tag($0.rawValue) }
                            }
                            DatePicker("A pay period began", selection: $paySchedule.anchorDate, displayedComponents: .date)
                        }.navigationTitle("Pay cycle").navigationBarTitleDisplayMode(.inline)
                    } label: { LabeledContent("Pay cycle", value: paySchedule.frequency.title) }
                }
            }

            if job.compensationKind == .salary { SalarySettingsSection(job: job) }

            Section {
                DisclosureGroup("Extra pay & scheduling") {
                    if job.compensationKind == .hourly {
                        NavigationLink("Overtime & night pay") {
                            extraHourlyPay
                        }
                        NavigationLink("Weekly schedule") { TemplatesView(selectedJobID: job.id) }
                    }
                    DisclosureGroup("Stipends & reimbursements") {
                        ForEach(supplements) { supplement in
                            Button { editingSupplement = supplement } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    LabeledContent(supplement.displayLabel, value: supplement.amountPerInterval.formatted(.currency(code: "USD")))
                                    Text(supplement.isEnabled ? supplement.frequency.title : "Off").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button("Add extra pay") { creatingSupplement = true }
                    }
                }
                NavigationLink("Job details") {
                    TimecardForm {
                        TextField("Job name", text: $job.name)
                        Picker("Color", selection: $job.accentRawValue) {
                            ForEach(JobAccentStyle.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        if job.compensationKind == .hourly { SalarySettingsSection(job: job) }
                    }.navigationTitle("Job details").navigationBarTitleDisplayMode(.inline)
                }
            }
            if activeJobCount > 1 {
                Section {
                    Button("Archive this job", role: .destructive) { confirmingDeletion = true }
                        .accessibilityIdentifier("settings.archiveJob")
                }
            }
        }
        .confirmationDialog(
            "Archive \(job.displayName)?",
            isPresented: $confirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("Archive \(job.displayName)", role: .destructive) {
                archiveJob()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Completed shifts stay in History. Future schedules and templates for this job are removed.")
        }
        .alert("Unable to Archive Job", isPresented: deleteErrorIsPresented) {
            Button("OK") {
                deleteErrorText = nil
            }
        } message: {
            Text(deleteErrorText ?? "")
        }
    }

    private var deleteErrorIsPresented: Binding<Bool> {
        Binding(
            get: { deleteErrorText != nil },
            set: { isPresented in
                if !isPresented {
                    deleteErrorText = nil
                }
            }
        )
    }

    private func archiveJob() {
        do {
            try JobService.archiveJob(job, in: modelContext)
            Task {
                await ReminderManager.shared.syncShiftReminders(
                    templates: templates,
                    isEnabled: preferences.first?.remindersEnabled ?? false
                )
            }
            dismiss()
        } catch {
            deleteErrorText = error.localizedDescription
        }
    }

    private var activeJobCount: Int {
        jobs.filter { !$0.isArchived }.count
    }

    private var extraHourlyPay: some View {
        TimecardForm {
            Section {
                Toggle("Overtime", isOn: $overtimeRule.isEnabled)
                if overtimeRule.isEnabled {
                    overtimeThreshold("Daily", hours: $overtimeRule.dailyThresholdHours, multiplier: $overtimeRule.dailyMultiplier, defaultHours: 8)
                    overtimeThreshold("Weekly", hours: $overtimeRule.weeklyThresholdHours, multiplier: $overtimeRule.weeklyMultiplier, defaultHours: 40)
                    if overtimeRule.weeklyThresholdHours != nil {
                        Picker("Workweek starts", selection: Binding(
                            get: { overtimeRule.workweekStartRawValue ?? Calendar.current.firstWeekday },
                            set: { overtimeRule.workweekStartRawValue = $0 })) {
                            ForEach(ScheduleWeekday.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                    }
                    if overtimeRule.dailyThresholdHours != nil && overtimeRule.weeklyThresholdHours != nil {
                        Picker("When both apply", selection: $overtimeRule.precedenceRawValue) {
                            Text("Higher rate").tag(OvertimePrecedence.highestRateWins.rawValue)
                            Text("Daily first").tag(OvertimePrecedence.dailyFirst.rawValue)
                            Text("Weekly first").tag(OvertimePrecedence.weeklyFirst.rawValue)
                        }
                    }
                }
            }
            Section {
                Toggle("Night premium", isOn: $nightRule.isEnabled)
                if nightRule.isEnabled {
                    DatePicker("From", selection: nightBonusStartBinding, displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: nightBonusEndBinding, displayedComponents: .hourAndMinute)
                    LabeledContent("Extra pay") {
                        TextField("Percent", value: Binding(get: { nightRule.percentIncrease }, set: { if $0.isFinite && $0 >= 0 { nightRule.percentIncrease = $0 } }), format: .percent)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .navigationTitle("Overtime & night pay").navigationBarTitleDisplayMode(.inline)
        .appKeyboardToolbar()
    }

    @ViewBuilder
    private func overtimeThreshold(_ title: String, hours: Binding<Double?>, multiplier: Binding<Double>, defaultHours: Double) -> some View {
        Toggle("\(title) overtime", isOn: Binding(
            get: { hours.wrappedValue != nil }, set: { hours.wrappedValue = $0 ? defaultHours : nil }))
        if hours.wrappedValue != nil {
            LabeledContent("After how many hours?") {
                TextField("Hours", value: Binding(get: { hours.wrappedValue ?? defaultHours },
                    set: { if $0.isFinite && $0 > 0 { hours.wrappedValue = $0 } }), format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("Pay multiplier") {
                TextField("Multiplier", value: Binding(get: { multiplier.wrappedValue },
                    set: { if $0.isFinite && $0 >= 1 { multiplier.wrappedValue = $0 } }), format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
        }
    }

    private var nightBonusStartBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: nightRule.startHour, minute: 0)) ?? .now
            },
            set: { newValue in
                nightRule.startHour = Calendar.current.component(.hour, from: newValue)
            }
        )
    }

    private var nightBonusEndBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: nightRule.endHour, minute: 0)) ?? .now
            },
            set: { newValue in
                nightRule.endHour = Calendar.current.component(.hour, from: newValue)
            }
        )
    }

}

private struct JobEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var onCreated: (JobProfile) -> Void = { _ in }
    @State private var name = ""
    @State private var errorText: String?

    var body: some View {
        TimecardForm {
            Section {
                TextField("Job name", text: $name).textInputAutocapitalization(.words)
            }

            if let errorText {
                Section {
                    AppInlineNotice(message: errorText)
                } header: {
                    Text("Issue")
                }
            }
        }
        .navigationTitle("Add Job")
        .navigationBarTitleDisplayMode(.inline)
        .appKeyboardToolbar()
        .scrollContentBackground(.hidden)
        .background(MoneyBackground())
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        do {
            let job = try JobService.createJob(
                in: modelContext,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            onCreated(job)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct SupplementEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let job: JobProfile
    let editingSupplement: JobSupplement?

    @State private var label: String
    @State private var kind: JobSupplementKind
    @State private var amountText: String
    @State private var frequency: PayFrequency
    @State private var anchorDate: Date
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var taxTreatment: SupplementTaxTreatment
    @State private var isEnabled: Bool
    @State private var errorText: String?

    init(job: JobProfile, editingSupplement: JobSupplement?) {
        self.job = job
        self.editingSupplement = editingSupplement

        let resolvedKind = editingSupplement?.kind ?? .housingStipend
        let resolvedAnchorDate = editingSupplement?.anchorDate ?? Calendar.current.startOfDay(for: .now)
        let resolvedStartDate = editingSupplement?.startDate ?? resolvedAnchorDate
        let resolvedEndDate = editingSupplement?.endDate ?? resolvedStartDate

        _label = State(initialValue: editingSupplement?.displayLabel ?? resolvedKind.suggestedLabel)
        _kind = State(initialValue: resolvedKind)
        _amountText = State(initialValue: editingSupplement.map {
            LocalizedNumericInput.decimalText(for: $0.amountPerInterval)
        } ?? "")
        _frequency = State(initialValue: editingSupplement?.frequency ?? .monthly)
        _anchorDate = State(initialValue: resolvedAnchorDate)
        _startDate = State(initialValue: resolvedStartDate)
        _hasEndDate = State(initialValue: editingSupplement?.endDate != nil)
        _endDate = State(initialValue: resolvedEndDate)
        _taxTreatment = State(initialValue: editingSupplement?.taxTreatment ?? resolvedKind.defaultTaxTreatment)
        _isEnabled = State(initialValue: editingSupplement?.isEnabled ?? true)
    }

    var body: some View {
        TimecardForm {
            Section {
                TextField("Label", text: $label)
                Picker("Type", selection: $kind) {
                    ForEach(JobSupplementKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                TextField("Amount per payment", text: $amountText)
                    .keyboardType(.decimalPad)
                Picker("Frequency", selection: $frequency) {
                    ForEach(PayFrequency.allCases) { frequency in
                        Text(frequency.title).tag(frequency)
                    }
                }
            } header: {
                Text("Compensation")
            }

            Section {
                DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    .onChange(of: startDate) { previous, new in
                        if anchorDate == previous { anchorDate = new }
                    }
                DisclosureGroup("More options") {
                    DatePicker("Pay cycle starts", selection: $anchorDate, displayedComponents: .date)
                    Toggle("Has an end date", isOn: $hasEndDate)
                    if hasEndDate { DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date) }
                    Toggle("Taxable", isOn: Binding(get: { taxTreatment == .taxable }, set: { taxTreatment = $0 ? .taxable : .nonTaxable }))
                    if editingSupplement != nil { Toggle("Enabled", isOn: $isEnabled) }
                }
            }

            if let editingSupplement {
                Section {
                    Button(role: .destructive) {
                        do {
                            modelContext.delete(editingSupplement)
                            try PersistenceService.save(modelContext)
                            dismiss()
                        } catch {
                            modelContext.rollback()
                            errorText = error.localizedDescription
                        }
                    } label: {
                        Text("Delete this supplemental item")
                    }
                } header: {
                    Text("Remove")
                }
            }

            if let errorText {
                Section {
                    AppInlineNotice(message: errorText)
                } header: {
                    Text("Issue")
                }
            }
        }
        .navigationTitle(editingSupplement == nil ? "Add Supplement" : "Edit Supplement")
        .navigationBarTitleDisplayMode(.inline)
        .appKeyboardToolbar()
        .scrollContentBackground(.hidden)
        .background(MoneyBackground())
        .onChange(of: kind) { oldKind, newKind in
            if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || label == oldKind.suggestedLabel {
                label = newKind.suggestedLabel
            }
            if editingSupplement == nil {
                taxTreatment = newKind.defaultTaxTreatment
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(!canSave)
            }
        }
    }

    private var parsedAmount: Double? {
        LocalizedNumericInput.decimalValue(from: amountText)
    }

    private var canSave: Bool {
        guard let parsedAmount else {
            return false
        }

        return parsedAmount > 0
    }

    private func save() {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLabel = trimmedLabel.isEmpty ? kind.suggestedLabel : trimmedLabel

        guard let parsedAmount, parsedAmount > 0 else {
            errorText = "Enter an amount greater than zero."
            return
        }

        let normalizedAnchorDate = Calendar.current.startOfDay(for: anchorDate)
        let normalizedStartDate = Calendar.current.startOfDay(for: startDate)
        let resolvedEndDate = hasEndDate ? Calendar.current.startOfDay(for: endDate) : nil

        if let resolvedEndDate, resolvedEndDate < normalizedStartDate {
            errorText = "The end date needs to be on or after the start date."
            return
        }

        if let editingSupplement {
            editingSupplement.label = resolvedLabel
            editingSupplement.kind = kind
            editingSupplement.amountPerInterval = parsedAmount
            editingSupplement.frequency = frequency
            editingSupplement.anchorDate = normalizedAnchorDate
            editingSupplement.startDate = normalizedStartDate
            editingSupplement.endDate = resolvedEndDate
            editingSupplement.taxTreatment = taxTreatment
            editingSupplement.isEnabled = isEnabled
            editingSupplement.updatedAt = .now
        } else {
            modelContext.insert(
                JobSupplement(
                    job: job,
                    label: resolvedLabel,
                    kind: kind,
                    amountPerInterval: parsedAmount,
                    frequency: frequency,
                    anchorDate: normalizedAnchorDate,
                    startDate: normalizedStartDate,
                    endDate: resolvedEndDate,
                    taxTreatment: taxTreatment,
                    isEnabled: isEnabled
                )
            )
        }

        do {
            try PersistenceService.save(modelContext)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct RateEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let job: JobProfile
    let editingRate: PayRateSchedule?

    @State private var effectiveDate: Date
    @State private var hourlyRateText: String
    @State private var errorText: String?

    init(job: JobProfile, editingRate: PayRateSchedule?) {
        self.job = job
        self.editingRate = editingRate
        _effectiveDate = State(initialValue: editingRate?.effectiveDate ?? Calendar.current.startOfDay(for: .now))
        _hourlyRateText = State(initialValue: editingRate.map {
            LocalizedNumericInput.decimalText(for: $0.hourlyRate)
        } ?? "")
    }

    var body: some View {
        TimecardForm {
            Section {
                DatePicker("Effective date", selection: $effectiveDate, displayedComponents: .date)
                TextField("Hourly rate", text: $hourlyRateText)
                    .keyboardType(.decimalPad)
            } header: {
                Text("Rate Details")
            }

            if let errorText {
                Section {
                    AppInlineNotice(message: errorText)
                } header: {
                    Text("Issue")
                }
            }
        }
        .navigationTitle(editingRate == nil ? "Add Rate" : "Edit Rate")
        .navigationBarTitleDisplayMode(.inline)
        .appKeyboardToolbar()
        .scrollContentBackground(.hidden)
        .background(MoneyBackground())
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let hourlyRate = parsedHourlyRate, hourlyRate > 0 else {
                        errorText = "Enter an hourly rate greater than zero."
                        return
                    }

                    let normalizedDate = Calendar.current.startOfDay(for: effectiveDate)
                    do {
                        let rates = try modelContext.fetch(FetchDescriptor<PayRateSchedule>())
                        if rates.contains(where: {
                            $0.job?.id == job.id && $0.id != editingRate?.id && Calendar.current.isDate($0.effectiveDate, inSameDayAs: normalizedDate)
                        }) {
                            errorText = "A rate already exists on this date. Edit that rate or choose another date."
                            return
                        }
                    } catch {
                        errorText = error.localizedDescription
                        return
                    }
                    if let editingRate {
                        editingRate.effectiveDate = normalizedDate
                        editingRate.hourlyRate = hourlyRate
                    } else {
                        modelContext.insert(PayRateSchedule(job: job, effectiveDate: normalizedDate, hourlyRate: hourlyRate))
                    }
                    do {
                        try PersistenceService.save(modelContext)
                        dismiss()
                    } catch {
                        modelContext.rollback()
                        errorText = error.localizedDescription
                    }
                }
                .disabled(!canSave)
            }
        }
    }

    private var parsedHourlyRate: Double? {
        LocalizedNumericInput.decimalValue(from: hourlyRateText)
    }

    private var canSave: Bool {
        guard let parsedHourlyRate else {
            return false
        }

        return parsedHourlyRate > 0
    }
}
