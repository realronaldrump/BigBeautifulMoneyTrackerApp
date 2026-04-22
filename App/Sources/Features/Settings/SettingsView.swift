import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [AppPreferences]
    @Query private var taxProfiles: [TaxProfile]
    @Query(sort: \JobProfile.sortOrder) private var jobs: [JobProfile]
    @Query private var templates: [ScheduleTemplate]

    @State private var creatingJob = false

    var body: some View {
        if let preferences = preferences.first,
           let taxProfile = taxProfiles.first {
            SettingsContent(
                preferences: preferences,
                taxProfile: taxProfile,
                jobs: jobs.filter { !$0.isArchived },
                templates: templates,
                creatingJob: $creatingJob
            )
            .sheet(isPresented: $creatingJob) {
                NavigationStack {
                    JobEditorView()
                }
            }
        } else {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.ignoresSafeArea())
                .task {
                    try? DataBootstrapper.seedIfNeeded(in: modelContext)
                }
        }
    }
}

private struct SettingsContent: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppTheme.self) private var theme

    @Bindable var preferences: AppPreferences
    @Bindable var taxProfile: TaxProfile

    let jobs: [JobProfile]
    let templates: [ScheduleTemplate]

    @Binding var creatingJob: Bool
    @State private var jobPendingDeletion: JobProfile?
    @State private var deleteErrorText: String?

    var body: some View {
        ZStack {
            MoneyBackground(mode: preferences.selectedDisplayMode)

            Form {
                Section {
                    BrandHeader(
                        eyebrow: "Settings",
                        subtitle: "Keep the home screen simple while each job carries its own rates, schedules, and shift rules.",
                        mode: preferences.selectedDisplayMode,
                        compact: true
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                Section {
                    Picker("Default Mode", selection: $preferences.selectedDisplayModeRawValue) {
                        Text("Gross").tag(EarningsDisplayMode.gross.rawValue)
                        Text("Estimated Take Home").tag(EarningsDisplayMode.takeHome.rawValue)
                    }
                    Toggle("Haptics", isOn: $preferences.hapticsEnabled)
                    Toggle("Live Activities", isOn: $preferences.liveActivitiesEnabled)
                    Toggle("Widgets", isOn: $preferences.lockScreenWidgetsEnabled)
                } header: {
                    settingsLabel("Main Screen", icon: "rectangle.on.rectangle", color: theme.grossAccent)
                }

                Section {
                    ForEach(jobs) { job in
                        NavigationLink {
                            JobSettingsView(job: job)
                        } label: {
                            HStack(spacing: 12) {
                                JobInitialBadge(name: job.displayName, accent: job.accent.color, size: 30)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(job.displayName)
                                    Text("Rates, overtime, payday, and templates")
                                        .font(.footnote)
                                        .foregroundStyle(theme.secondaryText)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                jobPendingDeletion = job
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .disabled(jobs.count <= 1)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                jobPendingDeletion = job
                            } label: {
                                Label("Delete Job", systemImage: "trash")
                            }
                            .disabled(jobs.count <= 1)
                        }
                    }

                    Button {
                        creatingJob = true
                    } label: {
                        HStack {
                            Label("Add another job", systemImage: "plus.circle")
                            Spacer()
                            Text("\(jobs.count)/\(JobService.maxJobs)")
                                .font(.footnote)
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                    .disabled(jobs.count >= JobService.maxJobs)
                } header: {
                    settingsLabel("Jobs", icon: "briefcase.fill", color: Color(red: 0.36, green: 0.53, blue: 0.96))
                } footer: {
                    Text("Each job keeps its own pay history, shift rules, and templates.")
                }

                Section {
                    Text("This stays an estimate, not an exact paycheck deposit.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText)

                    Picker("I file as", selection: $taxProfile.filingStatusRawValue) {
                        ForEach(FilingStatus.allCases) { status in
                            Text(status.title).tag(status.rawValue)
                        }
                    }
                    Toggle("Use the regular deduction most people with one job use", isOn: $taxProfile.usesStandardDeduction)
                    TextField("Insurance taken out over a year", value: $taxProfile.annualPretaxInsurance, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                    TextField("Retirement taken out over a year", value: $taxProfile.annualRetirementContribution, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)

                    DisclosureGroup("Advanced tax tweaks") {
                        TextField("Extra federal withholding per paycheck", value: $taxProfile.extraFederalWithholdingPerPeriod, format: .currency(code: "USD"))
                        TextField("Extra state withholding per paycheck", value: $taxProfile.extraStateWithholdingPerPeriod, format: .currency(code: "USD"))
                        TextField("Typical hours in a week", value: $taxProfile.expectedWeeklyHours, format: .number.precision(.fractionLength(1)))
                    }
                } header: {
                    settingsLabel("Take-Home Estimate", icon: "banknote.fill", color: theme.takeHomeAccent)
                }

                Section {
                    Toggle("Schedule reminders", isOn: $preferences.remindersEnabled)
                    Button("Request reminder permission") {
                        Task { await ReminderManager.shared.requestAuthorization() }
                    }
                    Button("Sync reminder schedule") {
                        Task {
                            await ReminderManager.shared.syncShiftReminders(
                                templates: templates,
                                isEnabled: preferences.remindersEnabled
                            )
                        }
                    }
                    NavigationLink("Manage templates") {
                        TemplatesView()
                    }
                } header: {
                    settingsLabel("Automation", icon: "gearshape.2.fill", color: Color(red: 0.58, green: 0.40, blue: 0.92))
                }

                Section {
                    Text("Your shift and pay data stays on this device by default.")
                    Text("The app does not require an account, employer login, or payroll-provider connection.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText)
                    Text("If your iPhone uses Apple-managed backup services, app data may be included according to your device settings.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText)
                } header: {
                    settingsLabel("Data & Access", icon: "lock.shield.fill", color: Color(red: 0.30, green: 0.72, blue: 0.68))
                }

                Section {
                    Text("Davis's Big Beautiful Money Tracker App is for individual hourly workers tracking their own shifts and earnings.")
                    Text("It is not tied to any employer, payroll provider, client, or organization, and it does not require an account.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText)
                } header: {
                    settingsLabel("About This App", icon: "heart.fill", color: theme.roseAccent)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .safeAreaPadding(.bottom, 120)
        .tint(theme.grossAccent)
        .confirmationDialog(
            "Delete Job?",
            isPresented: deleteConfirmationIsPresented,
            titleVisibility: .visible
        ) {
            if let jobPendingDeletion {
                Button("Delete \(jobPendingDeletion.displayName)", role: .destructive) {
                    archiveJob(jobPendingDeletion)
                }
            }
            Button("Cancel", role: .cancel) {
                jobPendingDeletion = nil
            }
        } message: {
            Text("This removes the job from active tracking and clears future schedules and templates. Completed shifts stay in History.")
        }
        .alert("Unable to Delete Job", isPresented: deleteErrorIsPresented) {
            Button("OK") {
                deleteErrorText = nil
            }
        } message: {
            Text(deleteErrorText ?? "")
        }
    }

    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { jobPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    jobPendingDeletion = nil
                }
            }
        )
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

    private func archiveJob(_ job: JobProfile) {
        jobPendingDeletion = nil

        do {
            try JobService.archiveJob(job, in: modelContext)
            Task {
                await ReminderManager.shared.syncShiftReminders(
                    templates: templates,
                    isEnabled: preferences.remindersEnabled
                )
            }
        } catch {
            deleteErrorText = error.localizedDescription
        }
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
                .background(MoneyBackground(mode: .gross))
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
                    try? modelContext.save()
                }
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.ignoresSafeArea())
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
    @Environment(AppTheme.self) private var theme

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
        Form {
            Section {
                BrandHeader(
                    eyebrow: job.displayName,
                    subtitle: "Everything below applies only to this job.",
                    mode: .gross,
                    compact: true
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section {
                TextField("Job name", text: $job.name)
                Picker("Accent", selection: $job.accentRawValue) {
                    ForEach(JobAccentStyle.allCases) { accent in
                        Text(accent.title).tag(accent.rawValue)
                    }
                }
            } header: {
                settingsLabel("Job Identity", icon: "person.crop.square.fill", color: job.accent.color)
            }

            Section {
                ForEach(payRates) { rate in
                    Button {
                        editingRate = rate
                    } label: {
                        HStack {
                            Text("Starting \(rate.effectiveDate.formatted(date: .abbreviated, time: .omitted))")
                            Spacer()
                            Text(rate.hourlyRate, format: .currency(code: "USD"))
                        }
                    }
                }

                Button("Add a pay change") {
                    creatingRate = true
                }
            } header: {
                settingsLabel("Hourly Pay", icon: "banknote.fill", color: theme.grossAccent)
            }

            Section {
                Picker("My paycheck arrives", selection: $paySchedule.frequencyRawValue) {
                    ForEach(PayFrequency.allCases) { frequency in
                        Text(frequency.title).tag(frequency.rawValue)
                    }
                }
                DatePicker("This pay period started on", selection: $paySchedule.anchorDate, displayedComponents: .date)
            } header: {
                settingsLabel("Pay Schedule", icon: "calendar.badge.clock", color: Color(red: 0.36, green: 0.53, blue: 0.96))
            }

            Section {
                if supplements.isEmpty {
                    Text("No recurring stipends or reimbursements yet.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText)
                } else {
                    ForEach(supplements) { supplement in
                        Button {
                            editingSupplement = supplement
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(supplement.displayLabel)
                                        .foregroundStyle(.primary)

                                    Text(supplementSummary(supplement))
                                        .font(.footnote)
                                        .foregroundStyle(theme.secondaryText)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(supplement.amountPerInterval, format: .currency(code: "USD"))
                                        .foregroundStyle(.primary)
                                    if !supplement.isEnabled {
                                        Text("Disabled")
                                            .font(.footnote)
                                            .foregroundStyle(theme.secondaryText)
                                    }
                                }
                            }
                        }
                    }
                }

                Button("Add supplemental compensation") {
                    creatingSupplement = true
                }
            } header: {
                settingsLabel("Supplemental Compensation", icon: "plus.rectangle.on.folder.fill", color: theme.takeHomeAccent)
            } footer: {
                Text("Add housing stipends, reimbursements, or other recurring amounts here. To reflect changes over time, add a new dated item instead of rewriting an old one.")
            }

            Section {
                Toggle("I get extra pay for night hours", isOn: $nightRule.isEnabled)
                if nightRule.isEnabled {
                    DatePicker("Night bonus starts", selection: nightBonusStartBinding, displayedComponents: .hourAndMinute)
                    DatePicker("Night bonus ends", selection: nightBonusEndBinding, displayedComponents: .hourAndMinute)
                    TextField("Extra pay percent", value: $nightRule.percentIncrease, format: .percent.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                }
            } header: {
                settingsLabel("Night Shift Bonus", icon: "moon.stars.fill", color: Color(red: 0.51, green: 0.43, blue: 0.95))
            }

            Section {
                Toggle("Overtime Tracking", isOn: $overtimeRule.isEnabled.animation(.easeInOut(duration: 0.25)))
            } header: {
                settingsLabel("Overtime", icon: "bolt.fill", color: Color(red: 0.98, green: 0.67, blue: 0.28))
            } footer: {
                Text("When enabled, hours beyond your thresholds earn a multiplied rate.")
            }

            if overtimeRule.isEnabled {
                Section {
                    HStack {
                        Text("Threshold")
                        Spacer()
                        TextField("hrs", value: Binding(
                            get: { overtimeRule.dailyThresholdHours ?? 8 },
                            set: { overtimeRule.dailyThresholdHours = $0 }
                        ), format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                        Text("hrs")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Rate Multiplier")
                        Spacer()
                        Text("×")
                            .foregroundStyle(.secondary)
                        TextField("×", value: $overtimeRule.dailyMultiplier, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                } header: {
                    settingsLabel("Daily Overtime", icon: "sun.max.fill", color: Color(red: 0.98, green: 0.73, blue: 0.25))
                } footer: {
                    Text("Hours beyond \(formattedThreshold(overtimeRule.dailyThresholdHours ?? 8)) in a single shift are paid at ×\(formattedMultiplier(overtimeRule.dailyMultiplier)).")
                }

                Section {
                    HStack {
                        Text("Threshold")
                        Spacer()
                        TextField("hrs", value: Binding(
                            get: { overtimeRule.weeklyThresholdHours ?? 40 },
                            set: { overtimeRule.weeklyThresholdHours = $0 }
                        ), format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                        Text("hrs")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Rate Multiplier")
                        Spacer()
                        Text("×")
                            .foregroundStyle(.secondary)
                        TextField("×", value: $overtimeRule.weeklyMultiplier, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                } header: {
                    settingsLabel("Weekly Overtime", icon: "calendar", color: Color(red: 0.32, green: 0.62, blue: 0.98))
                } footer: {
                    Text("Hours beyond \(formattedThreshold(overtimeRule.weeklyThresholdHours ?? 40)) in a work week are paid at ×\(formattedMultiplier(overtimeRule.weeklyMultiplier)).")
                }

                Section {
                    Picker(selection: $overtimeRule.precedenceRawValue) {
                        Label("Highest Rate Wins", systemImage: "arrow.up.to.line")
                            .tag(OvertimePrecedence.highestRateWins.rawValue)
                        Label("Apply Daily First", systemImage: "sun.max")
                            .tag(OvertimePrecedence.dailyFirst.rawValue)
                        Label("Apply Weekly First", systemImage: "calendar")
                            .tag(OvertimePrecedence.weeklyFirst.rawValue)
                    } label: {
                        Text("When Both Apply")
                    }
                } header: {
                    settingsLabel("Conflict Resolution", icon: "arrow.triangle.branch", color: theme.roseAccent)
                } footer: {
                    Text(precedenceExplanation)
                }
            }

            Section {
                NavigationLink("Manage templates for \(job.displayName)") {
                    TemplatesView(selectedJobID: job.id)
                }
            } header: {
                settingsLabel("Templates", icon: "calendar.badge.plus", color: Color(red: 0.30, green: 0.72, blue: 0.68))
            }

            Section {
                Button(role: .destructive) {
                    confirmingDeletion = true
                } label: {
                    HStack(spacing: 12) {
                        SettingsSectionIcon(icon: "trash.fill", color: theme.roseAccent)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Delete this job")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            Text("Past shifts stay in History")
                                .font(.footnote)
                                .foregroundStyle(theme.secondaryText)
                        }

                        Spacer()
                    }
                }
                .disabled(activeJobCount <= 1)
            } header: {
                settingsLabel("Remove Job", icon: "trash.fill", color: theme.roseAccent)
            } footer: {
                Text(removeJobFooter)
            }
        }
        .confirmationDialog(
            "Delete \(job.displayName)?",
            isPresented: $confirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete \(job.displayName)", role: .destructive) {
                archiveJob()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Completed shifts stay in History. Future schedules and templates for this job are removed.")
        }
        .alert("Unable to Delete Job", isPresented: deleteErrorIsPresented) {
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

    private var removeJobFooter: String {
        if activeJobCount <= 1 {
            return "Add another job before deleting this one."
        }
        return "This removes \(job.displayName) from active tracking and clears future schedules and templates for it."
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

    private func formattedThreshold(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(value))"
            : String(format: "%.1f", value)
    }

    private func formattedMultiplier(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func supplementSummary(_ supplement: JobSupplement) -> String {
        let startText = supplement.startDate.formatted(date: .abbreviated, time: .omitted)
        let endText = supplement.endDate.map { " • Ends \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
        let statusText = supplement.taxTreatment == .taxable ? "Taxable" : "Non-taxable"
        return "\(supplement.kind.title) • \(supplement.frequency.title) • Active from \(startText)\(endText) • \(statusText)"
    }

    private var precedenceExplanation: String {
        switch overtimeRule.precedence {
        case .highestRateWins:
            "If a shift qualifies for both daily and weekly overtime, the higher multiplier is applied."
        case .dailyFirst:
            "Daily overtime is calculated first. Remaining hours are then checked against the weekly threshold."
        case .weeklyFirst:
            "Weekly overtime is calculated first. Daily thresholds are applied to remaining hours."
        }
    }
}

private struct JobEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppTheme.self) private var theme

    @State private var name = ""
    @State private var accent: JobAccentStyle = .sky
    @State private var errorText: String?

    var body: some View {
        Form {
            Section {
                BrandHeader(
                    eyebrow: "New Job",
                    subtitle: "Create another tracked job. You can add its rates and rules right after this.",
                    mode: .gross,
                    compact: true
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section {
                TextField("Job name", text: $name)
                Picker("Accent", selection: $accent) {
                    ForEach(JobAccentStyle.allCases) { accent in
                        Text(accent.title).tag(accent)
                    }
                }
            } header: {
                settingsLabel("Job", icon: "briefcase.fill", color: accent.color)
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .foregroundStyle(.red)
                } header: {
                    settingsLabel("Issue", icon: "exclamationmark.triangle.fill", color: theme.roseAccent)
                }
            }
        }
        .navigationTitle("Add Job")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(MoneyBackground(mode: .gross))
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
            _ = try JobService.createJob(
                in: modelContext,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                accent: accent
            )
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct SupplementEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppTheme.self) private var theme

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
    @State private var showingScheduleHelp = false
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
        Form {
            Section {
                BrandHeader(
                    eyebrow: editingSupplement == nil ? "Add Supplemental Pay" : "Edit Supplemental Pay",
                    subtitle: "Keep stipends and reimbursements separate from hourly shift earnings for \(job.displayName).",
                    mode: .takeHome,
                    compact: true
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section {
                TextField("Label", text: $label)
                Picker("Type", selection: $kind) {
                    ForEach(JobSupplementKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                TextField("Amount per interval", text: $amountText)
                    .keyboardType(.decimalPad)
                Picker("Frequency", selection: $frequency) {
                    ForEach(PayFrequency.allCases) { frequency in
                        Text(frequency.title).tag(frequency)
                    }
                }
            } header: {
                settingsLabel("Compensation", icon: "banknote.fill", color: job.accent.color)
            }

            Section {
                DatePicker("Repeat cycle starts", selection: $anchorDate, displayedComponents: .date)
                DatePicker("First active day", selection: $startDate, displayedComponents: .date)
                SupplementSchedulePreviewCard(
                    frequency: frequency,
                    anchorDate: anchorDate,
                    startDate: startDate,
                    accent: theme.takeHomeAccent
                ) {
                    showingScheduleHelp = true
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 2, trailing: 0))
                .listRowBackground(Color.clear)
                Toggle("End on a specific date", isOn: $hasEndDate.animation(.easeInOut(duration: 0.2)))
                if hasEndDate {
                    DatePicker("End date", selection: $endDate, displayedComponents: .date)
                }
            } header: {
                settingsLabel("Schedule", icon: "calendar.badge.clock", color: theme.takeHomeAccent)
            } footer: {
                Text("Repeat cycle starts sets the repeating cadence. First active day is when this item actually starts counting.")
            }

            Section {
                Toggle(
                    "Taxable compensation",
                    isOn: Binding(
                        get: { taxTreatment == .taxable },
                        set: { taxTreatment = $0 ? .taxable : .nonTaxable }
                    )
                )
                Toggle("Enabled", isOn: $isEnabled)
            } header: {
                settingsLabel("Treatment", icon: "slider.horizontal.3", color: theme.grossAccent)
            } footer: {
                Text("When the setup changes over time, create a new dated item instead of overwriting the old one.")
            }

            if let editingSupplement {
                Section {
                    Button(role: .destructive) {
                        modelContext.delete(editingSupplement)
                        try? modelContext.save()
                        dismiss()
                    } label: {
                        Text("Delete this supplemental item")
                    }
                } header: {
                    settingsLabel("Remove", icon: "trash.fill", color: theme.roseAccent)
                }
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } header: {
                    settingsLabel("Issue", icon: "exclamationmark.triangle.fill", color: theme.roseAccent)
                }
            }
        }
        .navigationTitle(editingSupplement == nil ? "Add Supplement" : "Edit Supplement")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(MoneyBackground(mode: .takeHome))
        .sheet(isPresented: $showingScheduleHelp) {
            SupplementScheduleHelpSheet(
                frequency: frequency,
                anchorDate: anchorDate,
                startDate: startDate
            )
            .presentationDetents([.height(500), .medium])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: kind) { _, newKind in
            if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            try modelContext.save()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct RateEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppTheme.self) private var theme

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
        Form {
            Section {
                BrandHeader(
                    eyebrow: editingRate == nil ? "Add Rate" : "Edit Rate",
                    subtitle: "Keep the pay history for \(job.displayName) accurate.",
                    mode: .gross,
                    compact: true
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section {
                DatePicker("Effective date", selection: $effectiveDate, displayedComponents: .date)
                TextField("Hourly rate", text: $hourlyRateText)
                    .keyboardType(.decimalPad)
            } header: {
                settingsLabel("Rate Details", icon: "banknote.fill", color: job.accent.color)
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } header: {
                    settingsLabel("Issue", icon: "exclamationmark.triangle.fill", color: theme.roseAccent)
                }
            }
        }
        .navigationTitle(editingRate == nil ? "Add Rate" : "Edit Rate")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(MoneyBackground(mode: .gross))
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

                    if let editingRate {
                        editingRate.effectiveDate = effectiveDate
                        editingRate.hourlyRate = hourlyRate
                    } else {
                        modelContext.insert(PayRateSchedule(job: job, effectiveDate: effectiveDate, hourlyRate: hourlyRate))
                    }
                    try? modelContext.save()
                    dismiss()
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

private struct SupplementSchedulePreviewCard: View {
    @Environment(AppTheme.self) private var theme

    let frequency: PayFrequency
    let anchorDate: Date
    let startDate: Date
    let accent: Color
    let onHelpTapped: () -> Void

    private var calendar: Calendar { .current }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("How this timing works")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("The two dates do different jobs: one lines up the repeating cycle and the other turns the supplement on.")
                        .font(TypeStyle.caption)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button(action: onHelpTapped) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay {
                            Circle()
                                .strokeBorder(accent.opacity(0.35), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Explain supplement schedule dates")
            }

            VStack(alignment: .leading, spacing: 10) {
                SupplementScheduleInsightRow(
                    icon: "repeat",
                    tint: accent,
                    title: "Repeat cycle starts",
                    text: "Sets the repeating \(frequency.title.lowercased()) schedule. Right now it is anchored to \(formatted(anchorDate))."
                )

                SupplementScheduleInsightRow(
                    icon: "play.fill",
                    tint: theme.grossAccent,
                    title: "First active day",
                    text: "The supplement is ignored before \(formatted(startDate)). This is the first day it counts."
                )
            }

            Text(firstIntervalSummary)
                .font(TypeStyle.caption)
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accent.opacity(0.14))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(accent.opacity(0.22), lineWidth: 1)
                }
        }
        .padding(16)
        .glassCard(cornerRadius: CornerRadius.cardSmall, accent: accent, hasShadow: false)
    }

    private var firstIntervalSummary: String {
        if startsOnCycleBoundary {
            return "Because the first active day lands exactly on a cycle boundary, the first \(frequency.title.lowercased()) amount will count in full."
        }

        return "Because the first active day lands partway through the current cycle, the first \(frequency.title.lowercased()) amount will be prorated."
    }

    private var startsOnCycleBoundary: Bool {
        let schedule = PaySchedule(
            frequency: frequency,
            anchorDate: calendar.startOfDay(for: anchorDate)
        )
        let interval = ProjectionEngine.payPeriodInterval(
            for: calendar.startOfDay(for: startDate),
            schedule: schedule,
            calendar: calendar
        )

        return calendar.isDate(interval.start, inSameDayAs: startDate)
    }

    private func formatted(_ date: Date) -> String {
        calendar.startOfDay(for: date).formatted(date: .abbreviated, time: .omitted)
    }
}

private struct SupplementScheduleInsightRow: View {
    @Environment(AppTheme.self) private var theme

    let icon: String
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.95), tint.opacity(0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(text)
                    .font(TypeStyle.caption)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SupplementScheduleHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppTheme.self) private var theme

    let frequency: PayFrequency
    let anchorDate: Date
    let startDate: Date

    private var calendar: Calendar { .current }

    var body: some View {
        ZStack {
            MoneyBackground(mode: .takeHome)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("How These Dates Work")
                                .font(TypeStyle.title2)
                                .foregroundStyle(.white)

                            Text("One date defines the repeating schedule. The other date decides when this supplement actually starts counting.")
                                .font(TypeStyle.callout)
                                .foregroundStyle(theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 12)

                        Button("Done") {
                            dismiss()
                        }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.takeHomeAccent)
                    }

                    SupplementScheduleDefinitionCard(
                        accent: theme.takeHomeAccent,
                        icon: "repeat",
                        title: "Repeat cycle starts",
                        description: cycleDescription,
                        detail: "Current setting: \(formatted(anchorDate))"
                    )

                    SupplementScheduleDefinitionCard(
                        accent: theme.grossAccent,
                        icon: "play.fill",
                        title: "First active day",
                        description: startDescription,
                        detail: "Current setting: \(formatted(startDate))"
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("In plain English")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.takeHomeAccent)

                        Text(plainEnglishSummary)
                            .font(TypeStyle.callout)
                            .foregroundStyle(.white.opacity(0.94))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.cardSmall, style: .continuous)
                            .fill(theme.takeHomeAccent.opacity(0.12))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: CornerRadius.cardSmall, style: .continuous)
                            .strokeBorder(theme.takeHomeAccent.opacity(0.24), lineWidth: 1)
                    }
                }
                .padding(20)
                .glassCard(cornerRadius: CornerRadius.cardLarge, accent: theme.takeHomeAccent)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var cycleDescription: String {
        switch frequency {
        case .weekly:
            return "This sets where each weekly supplement interval begins. With \(formatted(anchorDate)), a new interval starts every 7 days from that date."
        case .biweekly:
            return "This sets where each biweekly supplement interval begins. With \(formatted(anchorDate)), a new interval starts every 14 days from that date."
        case .monthly:
            return "This sets the day-of-month that begins each supplement interval. With \(formatted(anchorDate)), each interval runs from day \(anchorDay) to the same day next month."
        case .semiMonthly:
            return "This sets how the month is split into two supplement intervals. With \(formatted(anchorDate)), the app uses day \(semiMonthlyBoundaryDay) and day 16 as the two boundaries."
        }
    }

    private var startDescription: String {
        if startsOnCycleBoundary {
            return "This is the first day the supplement is active. The app ignores the supplement before \(formatted(startDate)), and because this date lands on a cycle boundary, the first interval counts the full amount."
        }

        return "This is the first day the supplement is active. The app ignores the supplement before \(formatted(startDate)), and because this date lands inside an existing cycle, the first interval is prorated."
    }

    private var plainEnglishSummary: String {
        let cadence = frequency.title.lowercased()
        if startsOnCycleBoundary {
            return "This supplement repeats on a \(cadence) cycle anchored to \(formatted(anchorDate)). It starts counting on \(formatted(startDate)), which matches the start of a cycle, so the first amount will count in full."
        }

        return "This supplement repeats on a \(cadence) cycle anchored to \(formatted(anchorDate)). It only starts counting on \(formatted(startDate)), so anything before that date is ignored and the first amount will be prorated."
    }

    private var startsOnCycleBoundary: Bool {
        let schedule = PaySchedule(
            frequency: frequency,
            anchorDate: calendar.startOfDay(for: anchorDate)
        )
        let interval = ProjectionEngine.payPeriodInterval(
            for: calendar.startOfDay(for: startDate),
            schedule: schedule,
            calendar: calendar
        )

        return calendar.isDate(interval.start, inSameDayAs: startDate)
    }

    private var anchorDay: Int {
        calendar.component(.day, from: anchorDate)
    }

    private var semiMonthlyBoundaryDay: Int {
        min(anchorDay, 15)
    }

    private func formatted(_ date: Date) -> String {
        calendar.startOfDay(for: date).formatted(date: .abbreviated, time: .omitted)
    }
}

private struct SupplementScheduleDefinitionCard: View {
    @Environment(AppTheme.self) private var theme

    let accent: Color
    let icon: String
    let title: String
    let description: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.98), accent.opacity(0.68)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
                    }

                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text(description)
                .font(TypeStyle.callout)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(TypeStyle.caption)
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(accent.opacity(0.14))
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(accent.opacity(0.24), lineWidth: 1)
                }
        }
        .padding(16)
        .glassCard(cornerRadius: CornerRadius.cardSmall, accent: accent, hasShadow: false)
    }
}

private func settingsLabel(_ title: String, icon: String, color: Color) -> some View {
    SettingsSectionHeader(title: title, icon: icon, color: color)
}

private struct SettingsSectionHeader: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            SettingsSectionIcon(icon: icon, color: color)

            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.96))
        }
        .padding(.top, 6)
        .padding(.leading, 2)
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsSectionIcon: View {
    let icon: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            color.opacity(0.98),
                            color.opacity(0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
        }
        .shadow(color: color.opacity(0.32), radius: 10, y: 4)
        .accessibilityHidden(true)
    }
}
