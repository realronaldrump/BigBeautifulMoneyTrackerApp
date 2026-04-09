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
    @Query(sort: \PayRateSchedule.effectiveDate, order: .reverse) private var payRates: [PayRateSchedule]
    @Query private var templates: [ScheduleTemplate]

    @State private var editingRate: PayRateSchedule?
    @State private var creatingRate = false

    var body: some View {
        if let preferences = preferences.first,
           let taxProfile = taxProfiles.first,
           let paySchedule = paySchedules.first,
           let nightRule = nightRules.first,
           let overtimeRule = overtimeRules.first {
            SettingsContent(
                preferences: preferences,
                taxProfile: taxProfile,
                paySchedule: paySchedule,
                nightRule: nightRule,
                overtimeRule: overtimeRule,
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

    let payRates: [PayRateSchedule]
    let templates: [ScheduleTemplate]

    @Binding var editingRate: PayRateSchedule?
    @Binding var creatingRate: Bool

    var body: some View {
        ZStack {
            MoneyBackground(mode: preferences.selectedDisplayMode)

            Form {
                Section {
                    BrandHeader(
                        eyebrow: "Settings",
                        subtitle: "Davis's Big Beautiful Money Tracker App keeps your rules, rates, and reminders elegant while staying easy to tune.",
                        mode: preferences.selectedDisplayMode,
                        compact: true
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                Section("Main Screen") {
                    Picker("Default Mode", selection: $preferences.selectedDisplayModeRawValue) {
                        Text("Gross").tag(EarningsDisplayMode.gross.rawValue)
                        Text("Estimated Take Home").tag(EarningsDisplayMode.takeHome.rawValue)
                    }
                    Toggle("Haptics", isOn: $preferences.hapticsEnabled)
                    Toggle("Live Activities", isOn: $preferences.liveActivitiesEnabled)
                    Toggle("Widgets", isOn: $preferences.lockScreenWidgetsEnabled)
                }

                Section("Hourly Pay") {
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
                }

                Section("Night Shift Bonus") {
                    Toggle("I get extra pay for night hours", isOn: $nightRule.isEnabled)
                    if nightRule.isEnabled {
                        DatePicker("Night bonus starts", selection: nightBonusStartBinding, displayedComponents: .hourAndMinute)
                        DatePicker("Night bonus ends", selection: nightBonusEndBinding, displayedComponents: .hourAndMinute)
                        TextField("Extra pay percent", value: $nightRule.percentIncrease, format: .percent.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                        Text("Default: 7:00 PM to 7:00 AM with a 7% bump.")
                            .font(.footnote)
                            .foregroundStyle(theme.secondaryText)
                    }
                }

                Section("Overtime") {
                    Toggle("I want overtime tracking", isOn: $overtimeRule.isEnabled)
                    if overtimeRule.isEnabled {
                        Text("Only turn this on if your employer actually pays overtime.")
                            .font(.footnote)
                            .foregroundStyle(theme.secondaryText)

                        TextField("Overtime after this many hours in one day", value: Binding(
                            get: { overtimeRule.dailyThresholdHours ?? 8 },
                            set: { overtimeRule.dailyThresholdHours = $0 }
                        ), format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                        TextField("Overtime after this many hours in one week", value: Binding(
                            get: { overtimeRule.weeklyThresholdHours ?? 40 },
                            set: { overtimeRule.weeklyThresholdHours = $0 }
                        ), format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                        TextField("Daily overtime pays this many times normal pay", value: $overtimeRule.dailyMultiplier, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                        TextField("Weekly overtime pays this many times normal pay", value: $overtimeRule.weeklyMultiplier, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                        Picker("If both rules hit at once", selection: $overtimeRule.precedenceRawValue) {
                            Text("Use the higher overtime rate").tag(OvertimePrecedence.highestRateWins.rawValue)
                            Text("Use the daily rule first").tag(OvertimePrecedence.dailyFirst.rawValue)
                            Text("Use the weekly rule first").tag(OvertimePrecedence.weeklyFirst.rawValue)
                        }
                    }
                }

                Section("Take-Home Estimate") {
                    Text("This stays an estimate, not an exact paycheck deposit.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText)

                    Picker("I file as", selection: $taxProfile.filingStatusRawValue) {
                        ForEach(FilingStatus.allCases) { status in
                            Text(status.title).tag(status.rawValue)
                        }
                    }
                    Toggle("Use the regular deduction most people with one job use", isOn: $taxProfile.usesStandardDeduction)
                    Picker("My paycheck arrives", selection: $paySchedule.frequencyRawValue) {
                        ForEach(PayFrequency.allCases) { frequency in
                            Text(frequency.title).tag(frequency.rawValue)
                        }
                    }
                    DatePicker("This pay period started on", selection: $paySchedule.anchorDate, displayedComponents: .date)
                    TextField("Insurance taken out over a year", value: $taxProfile.annualPretaxInsurance, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                    TextField("Retirement taken out over a year", value: $taxProfile.annualRetirementContribution, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)

                    DisclosureGroup("Advanced tax tweaks") {
                        TextField("Extra federal withholding per paycheck", value: $taxProfile.extraFederalWithholdingPerPeriod, format: .currency(code: "USD"))
                        TextField("Extra state withholding per paycheck", value: $taxProfile.extraStateWithholdingPerPeriod, format: .currency(code: "USD"))
                        TextField("Typical hours in a week", value: $taxProfile.expectedWeeklyHours, format: .number.precision(.fractionLength(1)))
                    }
                }

                Section("Automation") {
                    Toggle("Schedule reminders", isOn: $preferences.remindersEnabled)
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

                Section("Data") {
                    Toggle("iCloud backup preference", isOn: $preferences.cloudSyncEnabled)
                    Text("Cloud sync stays local-first. Your data remains private and on-device first.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
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

private struct RateEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let editingRate: PayRateSchedule?

    @State private var effectiveDate: Date
    @State private var hourlyRate: Double

    init(editingRate: PayRateSchedule?) {
        self.editingRate = editingRate
        _effectiveDate = State(initialValue: editingRate?.effectiveDate ?? Calendar.current.startOfDay(for: .now))
        _hourlyRate = State(initialValue: editingRate?.hourlyRate ?? 33.29)
    }

    var body: some View {
        Form {
            Section {
                BrandHeader(
                    eyebrow: editingRate == nil ? "Add Rate" : "Edit Rate",
                    subtitle: "Keep pay changes beautifully current in Davis's Big Beautiful Money Tracker App.",
                    mode: .gross,
                    compact: true
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
            }

            DatePicker("Effective date", selection: $effectiveDate, displayedComponents: .date)
            TextField("Hourly rate", value: $hourlyRate, format: .currency(code: "USD"))
                .keyboardType(.decimalPad)
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
