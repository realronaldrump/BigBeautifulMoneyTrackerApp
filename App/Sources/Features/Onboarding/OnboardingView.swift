import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppTheme.self) private var theme

    @Query private var preferences: [AppPreferences]
    @Query private var taxProfiles: [TaxProfile]
    @Query private var paySchedules: [PaySchedule]
    @Query private var payRates: [PayRateSchedule]

    @State private var hourlyRate = 33.29
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
                        subtitle: "Davis's Big Beautiful Money Tracker App starts beautifully: your current setup is prefilled, so you only need to confirm the basics.",
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
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Your hourly pay", value: $hourlyRate, format: .currency(code: "USD"))
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

            taxProfile.filingStatus = .single
            taxProfile.usesStandardDeduction = true
            taxProfile.annualPretaxInsurance = 0
            taxProfile.annualRetirementContribution = 0
            taxProfile.expectedWeeklyHours = SharedConstants.fallbackExpectedWeeklyHours

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
