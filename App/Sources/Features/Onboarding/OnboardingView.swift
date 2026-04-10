import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppTheme.self) private var theme

    @Query private var preferences: [AppPreferences]
    @Query private var taxProfiles: [TaxProfile]
    @Query(sort: \JobProfile.sortOrder) private var jobs: [JobProfile]
    @Query private var payRates: [PayRateSchedule]

    @State private var hourlyRateText = ""
    @State private var payFrequency: PayFrequency = .biweekly
    @State private var anchorDate = Calendar.current.startOfDay(for: .now)
    @State private var errorText: String?

    var body: some View {
        ZStack {
            MoneyBackground(mode: .gross)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    BrandHeader(
                        eyebrow: "Welcome",
                        subtitle: "Built for individual hourly workers tracking their own shifts and pay, with no employer setup, invitation, or account required.",
                        mode: .gross
                    )
                    .padding(.top, 24)

                    formCard

                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.red)
                    }

                    Button(action: completeOnboarding) {
                        Text("Begin Tracking")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(theme.grossAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canBeginTracking)
                    .opacity(canBeginTracking ? 1 : 0.7)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
        }
        .task {
            try? DataBootstrapper.seedIfNeeded(in: modelContext)
        }
    }

    private var formCard: some View {
        VStack(spacing: 18) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Made for individual hourly workers")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Track your own shifts and earnings without joining a company, getting employer approval, or creating an account.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.secondaryText)
                }
            } label: {
                Label("Who It's For", systemImage: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(.white)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Your hourly pay", text: $hourlyRateText)
                        .keyboardType(.decimalPad)
                    Picker("My paycheck arrives", selection: $payFrequency) {
                        ForEach(PayFrequency.allCases) { frequency in
                            Text(frequency.title).tag(frequency)
                        }
                    }
                    DatePicker("This pay period started on", selection: $anchorDate, displayedComponents: .date)
                    Text("If you’re not sure, choose the day your current paycheck cycle began. You can change it later.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText)
                }
                .textFieldStyle(.roundedBorder)
            } label: {
                Label("Your Pay", systemImage: "dollarsign.ring")
                    .foregroundStyle(.white)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Take-home estimate defaults")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("For now I’ll estimate your take-home assuming you file single, this is your only income, and you use the regular deduction most people with one job use.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.secondaryText)

                    Text("If your paycheck needs a closer match later, you can fine-tune insurance, retirement, and tax details in Settings.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText)
                }
            } label: {
                Label("Take Home Estimate", systemImage: "sun.max.trianglebadge.exclamationmark")
                    .foregroundStyle(.white)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(theme.panelFill(for: .gross))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(theme.brandStroke, lineWidth: 1)
                )
        )
        .tint(theme.grossAccent)
    }

    private func completeOnboarding() {
        guard let hourlyRate = parsedHourlyRate, hourlyRate > 0 else {
            errorText = "Enter your hourly pay before continuing."
            return
        }

        do {
            try DataBootstrapper.seedIfNeeded(in: modelContext)

            let hadPreferences = preferences.first != nil
            let hadTaxProfile = taxProfiles.first != nil
            let existingJobs = jobs.filter { !$0.isArchived }

            let preferences = preferences.first ?? AppPreferences()
            let taxProfile = taxProfiles.first ?? TaxProfile()

            if !hadPreferences {
                modelContext.insert(preferences)
            }
            if !hadTaxProfile {
                modelContext.insert(taxProfile)
            }

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

            preferences.onboardingCompleted = true
            preferences.selectedDisplayMode = .gross
            preferences.selectedHomeJobIdentifier = job.id

            taxProfile.filingStatus = .single
            taxProfile.usesStandardDeduction = true
            taxProfile.annualPretaxInsurance = 0
            taxProfile.annualRetirementContribution = 0
            taxProfile.expectedWeeklyHours = SharedConstants.fallbackExpectedWeeklyHours

            paySchedule.frequency = payFrequency
            paySchedule.anchorDate = anchorDate

            if let existingRate = payRates
                .filter({ $0.job?.id == job.id })
                .sorted(by: { $0.effectiveDate < $1.effectiveDate })
                .last {
                existingRate.hourlyRate = hourlyRate
                existingRate.effectiveDate = anchorDate
            } else {
                modelContext.insert(PayRateSchedule(job: job, effectiveDate: anchorDate, hourlyRate: hourlyRate))
            }

            try modelContext.save()
            HapticManager.shared.fire(.success, enabled: preferences.hapticsEnabled)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private var parsedHourlyRate: Double? {
        LocalizedNumericInput.decimalValue(from: hourlyRateText)
    }

    private var canBeginTracking: Bool {
        guard let parsedHourlyRate else {
            return false
        }

        return parsedHourlyRate > 0
    }
}
