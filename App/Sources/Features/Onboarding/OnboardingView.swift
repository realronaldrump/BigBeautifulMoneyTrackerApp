import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppTheme.self) private var theme

    @Query private var payRates: [PayRateSchedule]

    @State private var compensationKind: CompensationKind = .hourly
    @State private var salaryDraft = SalarySetupDraft()
    @State private var hourlyRateText = ""
    @State private var payFrequency: PayFrequency = .biweekly
    @State private var anchorDate = Calendar.current.startOfDay(for: .now)
    @State private var importedPaycheck: PaycheckReference?
    @State private var errorText: String?
    @FocusState private var rateIsFocused: Bool

    var body: some View {
        ZStack {
            MoneyBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    BrandSignature()
                    TimecardHeading(title: "Set up your pay")
                    VStack(alignment: .leading, spacing: 18) {
                        PayStatementImportButton { statement in
                            importedPaycheck = statement.paycheck
                            if let rate = statement.hourlyRate {
                                hourlyRateText = LocalizedNumericInput.decimalText(for: rate)
                            }
                            salaryDraft.amountBasis = .perPaycheck
                            salaryDraft.amountText = LocalizedNumericInput.decimalText(for: statement.paycheck.gross)
                            if let frequency = statement.frequency {
                                payFrequency = frequency
                                salaryDraft.frequency = frequency
                            }
                            if let start = statement.periodStart {
                                anchorDate = start
                                salaryDraft.anchorDate = start
                                salaryDraft.effectiveDate = start
                                if let paid = statement.paidDate, statement.frequency != nil {
                                    let plan = salaryDraft.makePlan()
                                    let end = SalaryEngine.period(for: plan, at: start).end
                                    let offset = plan.calendar.dateComponents([.day], from: end, to: paid).day ?? 0
                                    if (-30...60).contains(offset) { salaryDraft.paydayOffsetDays = offset }
                                }
                            }
                        }
                        if let importedPaycheck {
                            LabeledContent("Gross pay", value: importedPaycheck.gross.formatted(.currency(code: "USD")))
                            LabeledContent("Take-home pay", value: importedPaycheck.net.formatted(.currency(code: "USD")))
                        }
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
                                .font(.system(.title, design: .default, weight: .bold))
                                .padding(16)
                                .background(TimecardColor.inset, in: RoundedRectangle(cornerRadius: 4))
                                if !hourlyRateText.isEmpty && !canBeginTracking {
                                    Text("Enter a valid amount greater than zero.")
                                        .font(TypeStyle.caption).foregroundStyle(theme.stopAccent)
                                }
                            }
                            DisclosureGroup("Pay cycle · " + payFrequency.title) {
                                Picker("Paid", selection: $payFrequency) {
                                    ForEach(PayFrequency.allCases) { Text($0.title).tag($0) }
                                }
                                DatePicker("A pay period began", selection: $anchorDate, displayedComponents: .date)
                            }
                        }
                    }
                    .padding(20)
                    .ruledSection()

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
                .buttonStyle(AppActionButtonStyle())
                .disabled(!canBeginTracking)
                if !canBeginTracking {
                    Text(compensationKind == .salary ? "Enter your salary and pay cycle to begin." : "Enter your hourly rate to begin.").font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(TimecardColor.stock.opacity(0.96))
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
            guard let preferences = try DataBootstrapper.first(AppPreferences.self, in: modelContext) else { return }

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

            job.paycheckReference = importedPaycheck

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
