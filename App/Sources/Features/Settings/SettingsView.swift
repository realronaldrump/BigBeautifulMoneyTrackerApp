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
    @Environment(AppTheme.self) private var theme

    @Bindable var preferences: AppPreferences
    @Bindable var taxProfile: TaxProfile

    let jobs: [JobProfile]
    let templates: [ScheduleTemplate]

    @Binding var creatingJob: Bool

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
    }
}

private struct JobSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var job: JobProfile

    @Query(sort: \PayRateSchedule.effectiveDate, order: .reverse) private var payRates: [PayRateSchedule]
    @Query private var nightRules: [NightDifferentialRule]
    @Query private var overtimeRules: [OvertimeRuleSet]
    @Query private var paySchedules: [PaySchedule]

    @State private var editingRate: PayRateSchedule?
    @State private var creatingRate = false

    private var jobPayRates: [PayRateSchedule] {
        payRates.filter { $0.job?.id == job.id }
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
                    paySchedule: paySchedule,
                    nightRule: nightRule,
                    overtimeRule: overtimeRule,
                    editingRate: $editingRate,
                    creatingRate: $creatingRate
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
    @Environment(AppTheme.self) private var theme

    @Bindable var job: JobProfile
    let payRates: [PayRateSchedule]
    @Bindable var paySchedule: PaySchedule
    @Bindable var nightRule: NightDifferentialRule
    @Bindable var overtimeRule: OvertimeRuleSet

    @Binding var editingRate: PayRateSchedule?
    @Binding var creatingRate: Bool

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

    private func formattedThreshold(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(value))"
            : String(format: "%.1f", value)
    }

    private func formattedMultiplier(_ value: Double) -> String {
        String(format: "%.2f", value)
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
