import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppTheme.self) private var theme

    @Query private var preferences: [AppPreferences]
    @Query private var taxProfiles: [TaxProfile]
    @Query(sort: \JobProfile.sortOrder) private var jobs: [JobProfile]
    @Query private var payRates: [PayRateSchedule]

    @State private var compensationKind: CompensationKind = .hourly
    @State private var salaryDraft = SalarySetupDraft()
    @State private var hourlyRateText = ""
    @State private var payFrequency: PayFrequency = .biweekly
    @State private var anchorDate = Calendar.current.startOfDay(for: .now)
    @State private var errorText: String?
    @FocusState private var rateIsFocused: Bool

    var body: some View {
        ZStack {
            MoneyBackground(mode: .gross)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    BrandHeader(eyebrow: "See what you earn", subtitle: "Watch your earnings grow with hourly shifts or automatic salary tracking.", mode: .gross)

                    VStack(alignment: .leading, spacing: 18) {
                        Text("Set up your pay").font(TypeStyle.title2).foregroundStyle(.white)
                            .accessibilityAddTraits(.isHeader)
                        Picker("How are you paid?", selection: $compensationKind) {
                            ForEach(CompensationKind.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                        if compensationKind == .salary {
                            SalarySetupFields(draft: $salaryDraft)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Hourly rate").font(TypeStyle.callout).foregroundStyle(theme.secondaryText)
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("$").foregroundStyle(theme.secondaryText)
                                    TextField("0.00", text: $hourlyRateText)
                                        .keyboardType(.decimalPad)
                                        .focused($rateIsFocused)
                                        .accessibilityLabel("Hourly rate in dollars")
                                    Text("/ hour").font(TypeStyle.callout).foregroundStyle(theme.secondaryText)
                                }
                                .font(.system(.title, design: .rounded, weight: .bold))
                                .padding(16)
                                .background(theme.secondaryPanel, in: RoundedRectangle(cornerRadius: 16))
                                if !hourlyRateText.isEmpty && !canBeginTracking {
                                    Text("Enter a valid amount greater than zero.")
                                        .font(TypeStyle.caption).foregroundStyle(theme.roseAccent)
                                }
                            }
                            Picker("Pay frequency", selection: $payFrequency) {
                                ForEach(PayFrequency.allCases) { frequency in Text(frequency.title).tag(frequency) }
                            }
                            DatePicker("Pay period began", selection: $anchorDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                            Text("Choose the first day of your current pay cycle. You can adjust it later in Settings.")
                                .font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(20)
                    .glassCard(accent: theme.grossAccent, hasShadow: false)

                    DisclosureGroup("How take-home is estimated") {
                        Text("Estimates start with single filing status, the standard deduction, and 2026 federal and Colorado tax rules. Adjust insurance, retirement, and tax details in Settings.")
                            .font(TypeStyle.callout).foregroundStyle(theme.secondaryText)
                            .padding(.top, 10).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(TypeStyle.callout).foregroundStyle(.white)
                    .padding(18).glassCard(hasShadow: false)

                    Label("Private on this iPhone. No account needed.", systemImage: "lock.shield")
                        .font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                    if let errorText { AppInlineNotice(message: errorText) }
                }
                .padding(20)
            }
        }
        .tint(theme.grossAccent)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                Button {
                    rateIsFocused = false
                    completeOnboarding()
                } label: { Label("Begin tracking", systemImage: "arrow.right") }
                .buttonStyle(AppActionButtonStyle(accent: theme.grossAccent))
                .disabled(!canBeginTracking)
                if !canBeginTracking {
                    Text(compensationKind == .salary ? "Enter your salary and pay cycle to begin." : "Enter your hourly rate to begin.").font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(theme.trueBlack.opacity(0.96))
        }
        .appKeyboardToolbar()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func completeOnboarding() {
        guard canBeginTracking else {
            errorText = "Enter valid pay details before continuing."
            return
        }

        do {
            try DataBootstrapper.seedIfNeeded(in: modelContext)

            let existingJobs = try JobService.jobs(in: modelContext)
            guard let preferences = try DataBootstrapper.first(AppPreferences.self, in: modelContext),
                  let taxProfile = try DataBootstrapper.first(TaxProfile.self, in: modelContext) else { return }

            let job: JobProfile
            if let existingJob = existingJobs.first {
                job = existingJob
            } else {
                job = try JobService.createJob(in: modelContext, name: "Main Job", accent: .emerald, anchorDate: anchorDate)
            }

            let storedPaySchedules = try modelContext.fetch(FetchDescriptor<PaySchedule>())
            let paySchedule = storedPaySchedules.first(where: { $0.job?.id == job.id }) ?? PaySchedule(job: job)
            if storedPaySchedules.contains(where: { $0.job?.id == job.id }) == false {
                modelContext.insert(paySchedule)
            }

            preferences.selectedDisplayMode = .gross
            preferences.selectedHomeJobIdentifier = job.id

            taxProfile.filingStatus = .single
            taxProfile.usesStandardDeduction = true
            taxProfile.annualPretaxInsurance = 0
            taxProfile.annualRetirementContribution = 0
            taxProfile.expectedWeeklyHours = SharedConstants.fallbackExpectedWeeklyHours

            if compensationKind == .salary {
                paySchedule.frequency = salaryDraft.frequency
                paySchedule.anchorDate = salaryDraft.anchorDate
                try SalaryService.savePlan(salaryDraft.makePlan(), for: job, in: modelContext, save: false)
            } else {
                paySchedule.frequency = payFrequency
                paySchedule.anchorDate = anchorDate

                if let existingRate = payRates
                    .filter({ $0.job?.id == job.id })
                    .sorted(by: { $0.effectiveDate < $1.effectiveDate })
                    .last {
                    existingRate.hourlyRate = parsedHourlyRate ?? 0
                    existingRate.effectiveDate = anchorDate
                } else {
                    modelContext.insert(PayRateSchedule(job: job, effectiveDate: anchorDate, hourlyRate: parsedHourlyRate ?? 0))
                }
            }

            preferences.onboardingCompleted = true
            try PersistenceService.save(modelContext)
            HapticManager.shared.fire(.success, enabled: preferences.hapticsEnabled)
        } catch {
            modelContext.rollback()
            errorText = error.localizedDescription
        }
    }

    private var parsedHourlyRate: Double? {
        LocalizedNumericInput.decimalValue(from: hourlyRateText)
    }

    private var canBeginTracking: Bool {
        if compensationKind == .salary { return salaryDraft.isValid }
        guard let parsedHourlyRate else {
            return false
        }

        return parsedHourlyRate > 0
    }
}
