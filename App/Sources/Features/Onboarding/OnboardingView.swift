import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppTheme.self) private var theme

    @Query private var preferences: [AppPreferences]
    @Query private var taxProfiles: [TaxProfile]
    @Query private var paySchedules: [PaySchedule]
    @Query private var payRates: [PayRateSchedule]

    @State private var hourlyRate = 42.0
    @State private var payFrequency: PayFrequency = .biweekly
    @State private var anchorDate = Calendar.current.startOfDay(for: .now)
    @State private var filingStatus: FilingStatus = .single
    @State private var usesStandardDeduction = true
    @State private var annualInsurance = 0.0
    @State private var annualRetirement = 0.0
    @State private var expectedWeeklyHours = SharedConstants.fallbackExpectedWeeklyHours
    @State private var errorText: String?

    var body: some View {
        ZStack {
            MoneyBackground(mode: .gross)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Big Beautiful Money Tracker App")
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Set the essentials once. After that, it’s one tap to start and one tap to stop.")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                    }
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
                VStack(spacing: 14) {
                    TextField("Hourly Rate", value: $hourlyRate, format: .currency(code: "USD"))
                    Picker("Pay Schedule", selection: $payFrequency) {
                        ForEach(PayFrequency.allCases) { frequency in
                            Text(frequency.title).tag(frequency)
                        }
                    }
                    DatePicker("Pay Period Anchor", selection: $anchorDate, displayedComponents: .date)
                }
                .textFieldStyle(.roundedBorder)
            } label: {
                Label("Compensation", systemImage: "dollarsign.ring")
                    .foregroundStyle(.white)
            }

            GroupBox {
                VStack(spacing: 14) {
                    Picker("Filing Status", selection: $filingStatus) {
                        ForEach(FilingStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    Toggle("Use standard deduction", isOn: $usesStandardDeduction)
                    TextField("Pre-tax insurance / year", value: $annualInsurance, format: .currency(code: "USD"))
                    TextField("Retirement contribution / year", value: $annualRetirement, format: .currency(code: "USD"))
                    TextField("Expected hours / week", value: $expectedWeeklyHours, format: .number.precision(.fractionLength(1)))
                }
                .textFieldStyle(.roundedBorder)
            } label: {
                Label("Take Home Estimate", systemImage: "sun.max.trianglebadge.exclamationmark")
                    .foregroundStyle(.white)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(theme.panel.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .tint(theme.grossAccent)
    }

    private func completeOnboarding() {
        do {
            try DataBootstrapper.seedIfNeeded(in: modelContext)

            let hadPreferences = preferences.first != nil
            let hadTaxProfile = taxProfiles.first != nil
            let hadPaySchedule = paySchedules.first != nil

            let preferences = preferences.first ?? AppPreferences()
            let taxProfile = taxProfiles.first ?? TaxProfile()
            let paySchedule = paySchedules.first ?? PaySchedule()

            if !hadPreferences {
                modelContext.insert(preferences)
            }
            if !hadTaxProfile {
                modelContext.insert(taxProfile)
            }
            if !hadPaySchedule {
                modelContext.insert(paySchedule)
            }

            preferences.onboardingCompleted = true
            preferences.selectedDisplayMode = .gross

            taxProfile.filingStatus = filingStatus
            taxProfile.usesStandardDeduction = usesStandardDeduction
            taxProfile.annualPretaxInsurance = annualInsurance
            taxProfile.annualRetirementContribution = annualRetirement
            taxProfile.expectedWeeklyHours = expectedWeeklyHours

            paySchedule.frequency = payFrequency
            paySchedule.anchorDate = anchorDate

            if let existingRate = payRates.sorted(by: { $0.effectiveDate < $1.effectiveDate }).last {
                existingRate.hourlyRate = hourlyRate
                existingRate.effectiveDate = anchorDate
            } else {
                modelContext.insert(PayRateSchedule(effectiveDate: anchorDate, hourlyRate: hourlyRate))
            }

            try modelContext.save()
            HapticManager.shared.fire(.success, enabled: preferences.hapticsEnabled)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
