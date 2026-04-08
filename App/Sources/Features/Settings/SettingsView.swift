import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppTheme.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @Query private var preferences: [AppPreferences]
    @Query private var taxProfiles: [TaxProfile]
    @Query private var paySchedules: [PaySchedule]
    @Query private var nightRules: [NightDifferentialRule]
    @Query private var overtimeRules: [OvertimeRuleSet]
    @Query private var workplaces: [WorkplaceLocation]
    @Query(sort: \PayRateSchedule.effectiveDate, order: .reverse) private var payRates: [PayRateSchedule]
    @Query private var templates: [ScheduleTemplate]

    @State private var editingRate: PayRateSchedule?
    @State private var creatingRate = false

    var body: some View {
        if let preferences = preferences.first,
           let taxProfile = taxProfiles.first,
           let paySchedule = paySchedules.first,
           let nightRule = nightRules.first,
           let overtimeRule = overtimeRules.first,
           let workplace = workplaces.first {
            SettingsContent(
                preferences: preferences,
                taxProfile: taxProfile,
                paySchedule: paySchedule,
                nightRule: nightRule,
                overtimeRule: overtimeRule,
                workplace: workplace,
                payRates: payRates,
                templates: templates,
                editingRate: $editingRate,
                creatingRate: $creatingRate
            )
            .sheet(item: $editingRate) { rate in
                NavigationStack {
                    RateEditorView(editingRate: rate)
                }
            }
            .sheet(isPresented: $creatingRate) {
                NavigationStack {
                    RateEditorView(editingRate: nil)
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
    @Environment(\.dismiss) private var dismiss

    @Bindable var preferences: AppPreferences
    @Bindable var taxProfile: TaxProfile
    @Bindable var paySchedule: PaySchedule
    @Bindable var nightRule: NightDifferentialRule
    @Bindable var overtimeRule: OvertimeRuleSet
    @Bindable var workplace: WorkplaceLocation

    let payRates: [PayRateSchedule]
    let templates: [ScheduleTemplate]

    @Binding var editingRate: PayRateSchedule?
    @Binding var creatingRate: Bool

    var body: some View {
        Form {
            Section("Display") {
                Picker("Default Mode", selection: $preferences.selectedDisplayModeRawValue) {
                    Text("Gross").tag(EarningsDisplayMode.gross.rawValue)
                    Text("Estimated Take Home").tag(EarningsDisplayMode.takeHome.rawValue)
                }
                Toggle("Haptics", isOn: $preferences.hapticsEnabled)
                Toggle("Live Activities", isOn: $preferences.liveActivitiesEnabled)
                Toggle("Widgets", isOn: $preferences.lockScreenWidgetsEnabled)
            }

            Section("Pay Rates") {
                ForEach(payRates) { rate in
                    Button {
                        editingRate = rate
                    } label: {
                        HStack {
                            Text(rate.effectiveDate.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Text(rate.hourlyRate, format: .currency(code: "USD"))
                        }
                    }
                }

                Button("Add Rate Change") {
                    creatingRate = true
                }
            }

            Section("Night Differential") {
                Toggle("Enabled", isOn: $nightRule.isEnabled)
                Stepper("Starts at \(nightRule.startHour):00", value: $nightRule.startHour, in: 0...23)
                Stepper("Ends at \(nightRule.endHour):00", value: $nightRule.endHour, in: 0...23)
                TextField("Percent increase", value: $nightRule.percentIncrease, format: .percent.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
            }

            Section("Overtime") {
                Toggle("Optional overtime module", isOn: $overtimeRule.isEnabled)
                TextField("Daily threshold hours", value: Binding(
                    get: { overtimeRule.dailyThresholdHours ?? 8 },
                    set: { overtimeRule.dailyThresholdHours = $0 }
                ), format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
                TextField("Weekly threshold hours", value: Binding(
                    get: { overtimeRule.weeklyThresholdHours ?? 40 },
                    set: { overtimeRule.weeklyThresholdHours = $0 }
                ), format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
                TextField("Daily multiplier", value: $overtimeRule.dailyMultiplier, format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad)
                TextField("Weekly multiplier", value: $overtimeRule.weeklyMultiplier, format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad)
                Picker("Precedence", selection: $overtimeRule.precedenceRawValue) {
                    ForEach(OvertimePrecedence.allCases) { precedence in
                        Text(precedence.title).tag(precedence.rawValue)
                    }
                }
            }

            Section("Take Home Estimate") {
                Picker("Filing Status", selection: $taxProfile.filingStatusRawValue) {
                    ForEach(FilingStatus.allCases) { status in
                        Text(status.title).tag(status.rawValue)
                    }
                }
                Toggle("Use standard deduction", isOn: $taxProfile.usesStandardDeduction)
                Picker("Pay Schedule", selection: $paySchedule.frequencyRawValue) {
                    ForEach(PayFrequency.allCases) { frequency in
                        Text(frequency.title).tag(frequency.rawValue)
                    }
                }
                DatePicker("Pay Period Anchor", selection: $paySchedule.anchorDate, displayedComponents: .date)
                TextField("Insurance / year", value: $taxProfile.annualPretaxInsurance, format: .currency(code: "USD"))
                TextField("Retirement / year", value: $taxProfile.annualRetirementContribution, format: .currency(code: "USD"))
                TextField("Extra federal / period", value: $taxProfile.extraFederalWithholdingPerPeriod, format: .currency(code: "USD"))
                TextField("Extra state / period", value: $taxProfile.extraStateWithholdingPerPeriod, format: .currency(code: "USD"))
                TextField("Expected hours / week", value: $taxProfile.expectedWeeklyHours, format: .number.precision(.fractionLength(1)))
            }

            Section("Automation") {
                Toggle("Schedule reminders", isOn: $preferences.remindersEnabled)
                Toggle("Geofencing prompts", isOn: $preferences.geofencingEnabled)
                Button("Request reminder permission") {
                    Task { await ReminderManager.shared.requestAuthorization() }
                }
                Button("Sync reminder schedule") {
                    Task {
                        await ReminderManager.shared.syncShiftReminders(templates: templates, isEnabled: preferences.remindersEnabled)
                    }
                }
                NavigationLink("Schedule templates") {
                    TemplatesView()
                }
            }

            Section("Workplace Geofence") {
                TextField("Latitude", value: Binding(
                    get: { workplace.latitude ?? 0 },
                    set: { workplace.latitude = $0 }
                ), format: .number.precision(.fractionLength(4...6)))
                    .keyboardType(.numbersAndPunctuation)
                TextField("Longitude", value: Binding(
                    get: { workplace.longitude ?? 0 },
                    set: { workplace.longitude = $0 }
                ), format: .number.precision(.fractionLength(4...6)))
                    .keyboardType(.numbersAndPunctuation)
                TextField("Radius (meters)", value: $workplace.radiusMeters, format: .number.precision(.fractionLength(0)))
                    .keyboardType(.decimalPad)
                Button("Request location permission") {
                    GeofenceManager.shared.requestAuthorization()
                }
                Button("Sync geofence") {
                    GeofenceManager.shared.syncMonitoring(workplace: workplace, isEnabled: preferences.geofencingEnabled)
                }
            }

            Section("Data") {
                Toggle("iCloud backup preference", isOn: $preferences.cloudSyncEnabled)
                Text("Cloud sync stays local-first. Your data remains private and on-device first.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") {
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
        .tint(theme.grossAccent)
    }
}

private struct RateEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let editingRate: PayRateSchedule?

    @State private var effectiveDate: Date
    @State private var hourlyRate: Double

    init(editingRate: PayRateSchedule?) {
        self.editingRate = editingRate
        _effectiveDate = State(initialValue: editingRate?.effectiveDate ?? Calendar.current.startOfDay(for: .now))
        _hourlyRate = State(initialValue: editingRate?.hourlyRate ?? 42)
    }

    var body: some View {
        Form {
            DatePicker("Effective date", selection: $effectiveDate, displayedComponents: .date)
            TextField("Hourly rate", value: $hourlyRate, format: .currency(code: "USD"))
                .keyboardType(.decimalPad)
        }
        .navigationTitle(editingRate == nil ? "Add Rate" : "Edit Rate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if let editingRate {
                        editingRate.effectiveDate = effectiveDate
                        editingRate.hourlyRate = hourlyRate
                    } else {
                        modelContext.insert(PayRateSchedule(effectiveDate: effectiveDate, hourlyRate: hourlyRate))
                    }
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
    }
}
